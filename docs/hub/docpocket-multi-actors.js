/**
 * ============================================================================
 * DOCPOCKET PRO — EXTENSION ARCHITECTURE MULTI-MÉDECINS & COCKPIT ASSURANCE
 * Fichier : docpocket-multi-actors.js
 * ============================================================================
 * - Séparation Chirurgicale : Volet Administratif (Clair) / Volet Médical (AES-GCM 256)
 * - Rétrocompatibilité totale avec les dossiers existants (Schema v1 -> v2)
 * - Machine à états temps réel : dispatched -> en_route -> on_site -> in_progress -> completed -> closed_paid
 * - Télémétrie GPS Live + Geofencing Hôtel automatique (150m)
 * - Transfert P2P GossipRelay des justificatifs GDP en blocs de 400 Ko
 * - Saisie manuelle stricte des dates au format jj/mm/aaaa sur tous les formulaires
 * ============================================================================
 */

(function (window) {
    'use strict';

    // ========================================================================
    // 0. UTILITAIRES GLOBAUX & VALIDATION STRICTE DES DATES (jj/mm/aaaa)
    // ========================================================================
    const DateValidator = {
        regex: /^(0[1-9]|[12][0-9]|3[01])\/(0[1-9]|1[0-2])\/(\d{4})$/,

        isValid(dateStr) {
            if (!dateStr || typeof dateStr !== 'string') return false;
            return this.regex.test(dateStr.trim());
        },

        /** Masque de saisie manuelle forcée jj/mm/aaaa */
        applyMask(inputElement) {
            let v = inputElement.value.replace(/\D/g, '');
            if (v.length >= 3 && v.length <= 4) {
                v = v.slice(0, 2) + '/' + v.slice(2);
            } else if (v.length >= 5) {
                v = v.slice(0, 2) + '/' + v.slice(2, 4) + '/' + v.slice(4, 8);
            }
            inputElement.value = v;
        },

        toTimestamp(dateStr) {
            if (!this.isValid(dateStr)) return null;
            const match = dateStr.trim().match(this.regex);
            return new Date(
                parseInt(match[3], 10),
                parseInt(match[2], 10) - 1,
                parseInt(match[1], 10)
            ).getTime();
        },

        todayFormatted() {
            const d = new Date();
            const jj   = String(d.getDate()).padStart(2, '0');
            const mm   = String(d.getMonth() + 1).padStart(2, '0');
            const aaaa = d.getFullYear();
            return `${jj}/${mm}/${aaaa}`;
        }
    };

    // ========================================================================
    // 1. MOTEUR DE STOCKAGE HYBRIDE (ADMIN CLAIR / MÉDICAL CHIFFRÉ AES-GCM 256)
    // ========================================================================
    const hybridStorageEngine = {

        bufferToBase64(buffer) {
            const bytes = new Uint8Array(buffer);
            let binary = '';
            for (let i = 0; i < bytes.byteLength; i++) binary += String.fromCharCode(bytes[i]);
            return window.btoa(binary);
        },

        base64ToBuffer(base64) {
            const binary = window.atob(base64);
            const bytes  = new Uint8Array(binary.length);
            for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
            return bytes.buffer;
        },

        async packConsultation(cleanV, pin, doctorProfile = {}) {
            if (cleanV.date && !DateValidator.isValid(cleanV.date)) {
                throw new Error("Format de date invalide. La saisie manuelle au format jj/mm/aaaa est obligatoire.");
            }

            // 1. Isolation stricte des données couvertes par le secret médical
            const medicalSecret = {
                reason:       cleanV.reason       || "",
                antecedents:  cleanV.antecedents  || "",
                clinicalExam: cleanV.clinicalExam || "",
                diagnosis:    cleanV.diagnosis    || "",
                treatment:    cleanV.treatment    || ""
            };

            // 2. Chiffrement AES-GCM 256 bits via cryptoUtils existant
            let encryptedBase64 = null;
            if (pin && window.cryptoUtils && typeof window.cryptoUtils.encrypt === 'function') {
                const encryptedBuffer = await window.cryptoUtils.encrypt(medicalSecret, pin, true);
                encryptedBase64 = this.bufferToBase64(encryptedBuffer);
            }

            // 3. Construction du paquet hybride v2
            return {
                schemaVersion: 2,
                id:         String(cleanV.id),
                doctorId:   doctorProfile.uid  || cleanV.doctorId   || "dr_default",
                doctorName: doctorProfile.name || cleanV.doctorName || "Médecin",
                status:     cleanV.status      || "completed",
                timestamps: cleanV.timestamps  || { updatedAt: Date.now() },

                /** Volet Administratif & Financier (Accessible temps réel par l'Opérateur Assurance) */
                adminData: {
                    name:        cleanV.name        || "",
                    numDossier:  cleanV.numDossier   || "",
                    age:         cleanV.age          || "",
                    nationality: cleanV.nationality  || "",
                    date:        cleanV.date         || DateValidator.todayFormatted(),
                    time:        cleanV.time         || "",
                    hotel:       cleanV.hotel        || "",
                    room:        cleanV.room         || "",
                    hotelLat:    cleanV.hotelLat     || null,
                    hotelLng:    cleanV.hotelLng     || null,
                    injections:  Boolean(cleanV.injections),
                    sutures:     Boolean(cleanV.sutures),
                    soinsLocaux: Boolean(cleanV.soinsLocaux),
                    coverage:    cleanV.coverage     || "Prise en charge",
                    partner:     cleanV.partner      || "",
                    fee:         String(cleanV.fee   || "0.000"),
                    tva:         String(cleanV.tva   || "7"),
                    paid:        Boolean(cleanV.paid),
                    hasScans:    Boolean(cleanV.hasScans),
                    hasGdp:      Boolean(cleanV.hasGdp),
                    gdpSynced:   Boolean(cleanV.gdpSynced)
                },

                /** Volet Médical Confidentiel Chiffré */
                medicalPayloadEncrypted: encryptedBase64,
                updatedAt: Date.now(),
                deleted:   Boolean(cleanV.deleted)
            };
        },

        async unpackConsultation(storedPacket, pin = null, userRole = 'doctor') {
            if (!storedPacket) return null;

            // Rétrocompatibilité Dossiers v1 (Entièrement chiffrés)
            if (!storedPacket.schemaVersion || storedPacket.schemaVersion !== 2) {
                if (!pin || !window.cryptoUtils) return null;
                const rawPayload = storedPacket.data ? storedPacket.data : storedPacket;
                return await window.cryptoUtils.decrypt(rawPayload, pin);
            }

            // Reconstruction de la base administrative (Schema v2)
            const baseVisit = {
                id:         storedPacket.id,
                doctorId:   storedPacket.doctorId,
                doctorName: storedPacket.doctorName,
                status:     storedPacket.status     || "completed",
                timestamps: storedPacket.timestamps || {},
                ...(storedPacket.adminData || {}),
                updatedAt:  storedPacket.updatedAt,
                deleted:    Boolean(storedPacket.deleted)
            };

            // Si Opérateur Assurance ou absence de PIN → masquage du secret médical
            if (userRole === 'insurance_operator' || !pin || !storedPacket.medicalPayloadEncrypted) {
                return {
                    ...baseVisit,
                    reason:       "🔒 [Confidentiel - Secret Médical]",
                    antecedents:  "🔒 [Confidentiel - Secret Médical]",
                    clinicalExam: "🔒 [Confidentiel - Secret Médical]",
                    diagnosis:    "🔒 [Confidentiel - Secret Médical]",
                    treatment:    "🔒 [Confidentiel - Secret Médical]",
                    isMedicalLocked: true
                };
            }

            // Déchiffrement du volet médical pour le médecin propriétaire
            try {
                const encryptedBuffer = this.base64ToBuffer(storedPacket.medicalPayloadEncrypted);
                const medicalSecret   = await window.cryptoUtils.decrypt(encryptedBuffer, pin);
                return { ...baseVisit, ...medicalSecret, isMedicalLocked: false };
            } catch (e) {
                console.warn("[DocPocket Multi-Actors] Volet médical verrouillé (PIN différent) :", e);
                return {
                    ...baseVisit,
                    reason:    "🔒 [Chiffré par un autre praticien]",
                    diagnosis: "🔒 [Chiffré par un autre praticien]",
                    treatment: "🔒 [Chiffré par un autre praticien]",
                    isMedicalLocked: true
                };
            }
        }
    };

    // ========================================================================
    // 2. MOTEUR GOSSIP RELAY GDP (DÉCOUPAGE ET TRANSFERT PAR BLOCS DE 400 Ko)
    // ========================================================================
    const gdpRelayEngine = {
        CHUNK_SIZE: 400000, // 400 Ko

        async uploadGdpInChunks(visitId, gdpBase64, deviceId = 'doc_device') {
            if (!window.db || !gdpBase64) return;
            const fileId      = `gdp_${visitId}`;
            const totalChunks = Math.ceil(gdpBase64.length / this.CHUNK_SIZE);

            const promises = [];
            for (let i = 0; i < totalChunks; i++) {
                const chunkData  = gdpBase64.slice(i * this.CHUNK_SIZE, (i + 1) * this.CHUNK_SIZE);
                const chunkDocId = `${fileId}___${deviceId}_chunk_${i}`;
                promises.push(
                    window.db.collection('relay_files').doc(chunkDocId).set({
                        fileId:      fileId,
                        visitId:     String(visitId),
                        chunkIndex:  i,
                        totalChunks: totalChunks,
                        data:        chunkData,
                        updatedAt:   Date.now()
                    })
                );
            }

            await Promise.all(promises);
            await window.db.collection('consultations').doc(String(visitId)).update({
                'adminData.hasGdp':    true,
                'adminData.gdpSynced': true,
                updatedAt: Date.now()
            });
        },

        initDoctorMediaRequestListener(doctorId) {
            if (!window.db || !window.localforage) return;
            window.db.collection('media_requests')
                .where('doctorId', '==', doctorId)
                .where('status',   '==', 'pending')
                .onSnapshot(async (snap) => {
                    for (const change of snap.docChanges()) {
                        if (change.type === 'added') {
                            const req      = change.doc.data();
                            const localGdp = await window.localforage.getItem(`gdp_${req.visitId}`);
                            if (localGdp) {
                                await this.uploadGdpInChunks(req.visitId, localGdp, doctorId);
                                await window.db.collection('media_requests').doc(change.doc.id).update({
                                    status:      'fulfilled',
                                    fulfilledAt: Date.now()
                                });
                            }
                        }
                    }
                });
        },

        async fetchAndAssembleGdp(visitId, doctorId) {
            const fileId = `gdp_${visitId}`;
            const snap   = await window.db.collection('relay_files')
                .where('fileId', '==', fileId)
                .get();

            if (snap.empty) {
                await window.db.collection('media_requests').doc(`req_${fileId}`).set({
                    visitId:     String(visitId),
                    doctorId:    doctorId || 'dr_default',
                    fileType:    'gdp',
                    status:      'pending',
                    requestedAt: Date.now()
                });
                throw new Error("PULL_REQUESTED");
            }

            const chunks = snap.docs.map(d => d.data());
            chunks.sort((a, b) => a.chunkIndex - b.chunkIndex);
            return chunks.map(c => c.data).join('');
        }
    };

    // ========================================================================
    // 3. MODULE MÉDECIN : MACHINE À ÉTATS TEMPS RÉEL & TÉLÉMÉTRIE GPS LIVE
    // ========================================================================
    const doctorMissionManager = {
        watchId:       null,
        activeMission: null,
        lastGpsSentAt: 0,
        doctorId:      null,
        doctorName:    null,

        init(doctorId, doctorName) {
            this.doctorId   = doctorId;
            this.doctorName = doctorName;
            if (!window.db) return;

            window.db.collection('consultations')
                .where('doctorId', '==', doctorId)
                .where('status',   'in', ['dispatched', 'en_route', 'on_site', 'in_progress'])
                .onSnapshot(snap => {
                    if (snap.empty) {
                        this.activeMission = null;
                        this.stopGpsTelemetry('available');
                        this.renderBanner(null);
                        return;
                    }

                    const doc          = snap.docs[0];
                    this.activeMission = { id: doc.id, ...doc.data() };
                    this.renderBanner(this.activeMission);

                    if (this.activeMission.status === 'en_route') {
                        this.startGpsTelemetry(this.activeMission);
                    } else {
                        this.stopGpsTelemetry(this.activeMission.status);
                    }
                });
        },

        async updateStatus(newStatus) {
            if (!this.activeMission || !window.db) return;
            const missionId = String(this.activeMission.id);

            await window.db.collection('consultations').doc(missionId).update({
                status: newStatus,
                [`timestamps.${newStatus}At`]: Date.now(),
                updatedAt: Date.now()
            });

            if (newStatus === 'in_progress' && window.app) {
                const unpacked = await hybridStorageEngine.unpackConsultation(
                    this.activeMission,
                    window.app.userPin,
                    'doctor'
                );
                if (unpacked) {
                    const idx = window.app.visits.findIndex(v => String(v.id) === missionId);
                    if (idx === -1) window.app.visits.unshift(unpacked);
                    else window.app.visits[idx] = unpacked;

                    if (typeof window.app.showForm === 'function') window.app.showForm(missionId);
                }
            }
        },

        startGpsTelemetry(mission) {
            if (this.watchId !== null || !navigator.geolocation) return;

            this.watchId = navigator.geolocation.watchPosition(
                async (pos) => {
                    const now = Date.now();
                    if (now - this.lastGpsSentAt < 20000) return; // Throttle 20 s
                    this.lastGpsSentAt = now;

                    const lat = pos.coords.latitude;
                    const lng = pos.coords.longitude;

                    if (window.db) {
                        await window.db.collection('doctors_telemetry').doc(this.doctorId).set({
                            doctorId:        this.doctorId,
                            name:            this.doctorName,
                            isAvailable:     false,
                            status:          'en_route',
                            currentMissionId: mission.id,
                            lat:             lat,
                            lng:             lng,
                            lastPing:        now
                        }, { merge: true });
                    }

                    // Geofencing automatique à 150 m de l'hôtel
                    const hLat  = mission.adminData?.hotelLat;
                    const hLng  = mission.adminData?.hotelLng;
                    if (hLat && hLng) {
                        const distKm = insuranceCockpit.getDistanceKm(lat, lng, hLat, hLng);
                        if (parseFloat(distKm) <= 0.15 && mission.status === 'en_route') {
                            this.updateStatus('on_site');
                        }
                    }
                },
                (err) => console.warn("[GPS Live] Erreur :", err),
                { enableHighAccuracy: true, maximumAge: 10000 }
            );
        },

        stopGpsTelemetry(statusLabel = 'available') {
            if (this.watchId !== null) {
                navigator.geolocation.clearWatch(this.watchId);
                this.watchId = null;
            }
            if (window.db && this.doctorId) {
                window.db.collection('doctors_telemetry').doc(this.doctorId).set({
                    doctorId:    this.doctorId,
                    name:        this.doctorName,
                    isAvailable: statusLabel === 'available',
                    status:      statusLabel,
                    updatedAt:   Date.now()
                }, { merge: true });
            }
        },

        renderBanner(mission) {
            let banner = document.getElementById('dp-doctor-mission-banner');
            if (!banner) {
                banner = document.createElement('div');
                banner.id = 'dp-doctor-mission-banner';
                document.body.prepend(banner);
            }

            if (!mission) { banner.style.display = 'none'; return; }

            const adm = mission.adminData || {};
            banner.style.cssText = "background:#0f172a;color:#fff;padding:10px 16px;display:flex;flex-wrap:wrap;gap:10px;justify-content:space-between;align-items:center;box-shadow:0 4px 12px rgba(0,0,0,0.25);z-index:9999;font-family:system-ui,sans-serif;";

            let btnHtml = '';
            if (mission.status === 'dispatched') {
                btnHtml = `<button onclick="window.DocPocketMultiActors.doctorMissionManager.updateStatus('en_route')" style="background:#2563eb;color:#fff;border:none;padding:8px 14px;border-radius:6px;font-weight:bold;cursor:pointer;">🚗 Accepter &amp; En Route (GPS)</button>`;
            } else if (mission.status === 'en_route') {
                btnHtml = `<button onclick="window.DocPocketMultiActors.doctorMissionManager.updateStatus('on_site')" style="background:#9333ea;color:#fff;border:none;padding:8px 14px;border-radius:6px;font-weight:bold;cursor:pointer;">🏨 Arrivé à l'Hôtel</button>`;
            } else if (mission.status === 'on_site') {
                btnHtml = `<button onclick="window.DocPocketMultiActors.doctorMissionManager.updateStatus('in_progress')" style="background:#db2777;color:#fff;border:none;padding:8px 14px;border-radius:6px;font-weight:bold;cursor:pointer;">🩺 Ouvrir Fiche &amp; Examiner</button>`;
            } else if (mission.status === 'in_progress') {
                btnHtml = `<span style="color:#4ade80;font-weight:bold;font-size:13px;">📝 Consultation en cours (Sauvegardez pour clôturer)</span>`;
            }

            banner.innerHTML = `
                <div style="font-size:13px;">
                    <span style="background:#dc2626;padding:3px 8px;border-radius:4px;font-size:11px;font-weight:bold;margin-right:8px;">URGENCE / ASSURANCE</span>
                    <b>${adm.hotel || 'Hôtel'} (Ch. ${adm.room || '-'})</b> — Patient : <b>${adm.name || '-'}</b> (${adm.partner || '-'}) — <span style="font-family:monospace;">${adm.date || ''} ${adm.time || ''}</span>
                </div>
                <div>${btnHtml}</div>
            `;
        }
    };

    // ========================================================================
    // 4. MODULE COMPTABILITÉ CONSOLIDÉE MULTI-MÉDECINS (PDF & CSV)
    // ========================================================================
    const accountingConsolidator = {

        formatActs(v) {
            const acts = ['Consultation'];
            if (v.injections)  acts.push('Injection');
            if (v.sutures)     acts.push('Suture');
            if (v.soinsLocaux) acts.push('Soins locaux');
            return `${acts.join(' + ')} (${v.coverage || 'Prise en charge'})`;
        },

        getFilteredConsultations() {
            const startStr  = document.getElementById('dp-bilan-start')?.value.trim();
            const endStr    = document.getElementById('dp-bilan-end')?.value.trim();
            const docFilter  = document.getElementById('dp-bilan-doctor')?.value || 'ALL';
            const paidFilter = document.getElementById('dp-bilan-paid')?.value   || 'ALL';

            if (startStr && !DateValidator.isValid(startStr)) {
                throw new Error("La Date Début doit être saisie manuellement au format strict jj/mm/aaaa.");
            }
            if (endStr && !DateValidator.isValid(endStr)) {
                throw new Error("La Date Fin doit être saisie manuellement au format strict jj/mm/aaaa.");
            }

            const startTs = startStr ? DateValidator.toTimestamp(startStr) : null;
            const endTs   = endStr   ? DateValidator.toTimestamp(endStr)   : null;

            return (insuranceCockpit.cachedConsultations || []).filter(v => {
                if (v.deleted) return false;
                const vTs = DateValidator.toTimestamp(v.date);
                if (startTs && (!vTs || vTs < startTs)) return false;
                if (endTs   && (!vTs || vTs > endTs))   return false;
                if (docFilter  !== 'ALL' && v.doctorId !== docFilter)  return false;
                if (paidFilter === 'PAID'   && !v.paid)  return false;
                if (paidFilter === 'UNPAID' &&  v.paid)  return false;
                return true;
            });
        },

        exportPDF() {
            try {
                if (!window.jspdf || !window.jspdf.jsPDF) {
                    alert("La librairie jsPDF n'est pas chargée. Ajoutez-la dans index.html."); return;
                }
                const rows = this.getFilteredConsultations();
                const { jsPDF } = window.jspdf;
                const doc = new jsPDF('landscape', 'mm', 'a4');

                const startStr = document.getElementById('dp-bilan-start')?.value || 'Début';
                const endStr   = document.getElementById('dp-bilan-end')?.value   || DateValidator.todayFormatted();

                doc.setFontSize(14);
                doc.text("BILAN COMPTABLE CONSOLIDÉ MULTI-MÉDECINS — DOCPOCKET PRO", 14, 15);
                doc.setFontSize(10);
                doc.text(`Période : du ${startStr} au ${endStr}`, 14, 22);

                let totalGeneral = 0, totalPaye = 0, totalNonPaye = 0;

                const body = rows.map(v => {
                    const fee = parseFloat(v.fee) || 0;
                    totalGeneral += fee;
                    if (v.paid) totalPaye += fee; else totalNonPaye += fee;
                    return [
                        v.numDossier || '-',
                        v.date       || '-',
                        `${v.name || ''}\n(${v.hotel || ''} Ch.${v.room || ''})`,
                        v.doctorName || v.doctorId || '-',
                        this.formatActs(v),
                        v.paid ? 'Oui' : 'Non',
                        `${fee.toFixed(3)} DT`
                    ];
                });

                doc.autoTable({
                    startY:     27,
                    head:       [['N° Dossier', 'Date', 'Patient & Hôtel', 'Médecin', 'Détails des actes', 'Payé', 'Net Comptabilisé']],
                    body:       body,
                    theme:      'grid',
                    headStyles: { fillColor: [30, 41, 59], textColor: 255 },
                    styles:     { fontSize: 9, cellPadding: 3 },
                    foot: [
                        ['', '', '', '', 'TOTAL PAYÉ',     'Oui', `${totalPaye.toFixed(3)} DT`],
                        ['', '', '', '', 'TOTAL NON PAYÉ', 'Non', `${totalNonPaye.toFixed(3)} DT`],
                        ['', '', '', '', 'TOTAL GÉNÉRAL',  '',    `${totalGeneral.toFixed(3)} DT`]
                    ],
                    footStyles: { fillColor: [241, 245, 249], textColor: [15, 23, 42], fontStyle: 'bold' }
                });

                doc.save(`Bilan_Multi_Medecins_${startStr.replace(/\//g, '-')}.pdf`);
            } catch (err) { alert(err.message); }
        },

        exportCSV() {
            try {
                const rows    = this.getFilteredConsultations();
                const headers = ['N° Dossier', 'Date', 'Patient', 'Hôtel', 'Chambre', 'Médecin', 'Partenaire', 'Détails des actes', 'Payé', 'Net Comptabilisé'];
                const lines   = [
                    headers.join(';'),
                    ...rows.map(v => [
                        `"${(v.numDossier || '').replace(/"/g, '""')}"`,
                        `"${v.date || ''}"`,
                        `"${(v.name   || '').replace(/"/g, '""')}"`,
                        `"${(v.hotel  || '').replace(/"/g, '""')}"`,
                        `"${v.room    || ''}"`,
                        `"${(v.doctorName || '').replace(/"/g, '""')}"`,
                        `"${(v.partner    || '').replace(/"/g, '""')}"`,
                        `"${this.formatActs(v)}"`,
                        v.paid ? 'Oui' : 'Non',
                        (parseFloat(v.fee) || 0).toFixed(3).replace('.', ',')
                    ].join(';'))
                ];

                const blob = new Blob(["\uFEFF" + lines.join('\n')], { type: 'text/csv;charset=utf-8;' });
                const url  = URL.createObjectURL(blob);
                const a    = document.createElement('a');
                a.href     = url;
                a.download = `Bilan_Multi_Medecins_${DateValidator.todayFormatted().replace(/\//g, '-')}.csv`;
                a.click();
                URL.revokeObjectURL(url);
            } catch (err) { alert(err.message); }
        }
    };

    // ========================================================================
    // 5. COCKPIT OPÉRATEUR ASSURANCE (UI AUTO-INJECTÉE + CARTE LIVE + DISPATCH)
    // ========================================================================
    const insuranceCockpit = {
        map:                  null,
        doctorMarkers:        {},
        doctorsTelemetry:     {},
        cachedConsultations:  [],
        hotelsDb:             [],

        async openCockpit(hotelsList = []) {
            this.hotelsDb = hotelsList;
            await this.ensureLeafletLoaded();
            this.injectCockpitHTML();
            this.initMap();
            this.populateHotelsDatalist();
            this.listenToDoctorsGPS();
            this.listenToConsultations();
        },

        ensureLeafletLoaded() {
            return new Promise((resolve) => {
                if (window.L) return resolve();
                const css  = document.createElement('link');
                css.rel    = 'stylesheet';
                css.href   = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.css';
                document.head.appendChild(css);

                const script    = document.createElement('script');
                script.src      = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.js';
                script.onload   = resolve;
                document.head.appendChild(script);
            });
        },

        injectCockpitHTML() {
            let container = document.getElementById('dp-insurance-cockpit-overlay');
            if (container) { container.style.display = 'grid'; return; }

            container = document.createElement('div');
            container.id         = 'dp-insurance-cockpit-overlay';
            container.style.cssText = "position:fixed;inset:0;background:#f1f5f9;z-index:9998;display:grid;grid-template-columns:360px 1fr;gap:14px;padding:14px;font-family:system-ui,sans-serif;overflow:hidden;";

            container.innerHTML = `
                <!-- COLONNE GAUCHE : FORMULAIRE DE DISPATCH -->
                <div style="background:#fff;border-radius:10px;padding:16px;box-shadow:0 2px 8px rgba(0,0,0,0.08);overflow-y:auto;display:flex;flex-direction:column;justify-content:space-between;">
                    <div>
                        <div style="display:flex;justify-content:space-between;align-items:center;border-bottom:2px solid #e2e8f0;padding-bottom:10px;margin-bottom:12px;">
                            <h3 style="margin:0;color:#0f172a;font-size:16px;">🚑 Dispatch Assurance</h3>
                            <button onclick="document.getElementById('dp-insurance-cockpit-overlay').style.display='none'" style="background:#e2e8f0;border:none;padding:4px 10px;border-radius:6px;cursor:pointer;font-weight:bold;">Fermer ✕</button>
                        </div>

                        <form id="dp-dispatch-form">
                            <div style="margin-bottom:8px;">
                                <label style="font-size:12px;font-weight:bold;">Patient (Nom &amp; Prénom) *</label>
                                <input type="text" id="dp-disp-name" required style="width:100%;padding:7px;border:1px solid #cbd5e1;border-radius:6px;box-sizing:border-box;">
                            </div>

                            <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:8px;">
                                <div>
                                    <label style="font-size:12px;font-weight:bold;">N° Dossier / Passeport *</label>
                                    <input type="text" id="dp-disp-dossier" required style="width:100%;padding:7px;border:1px solid #cbd5e1;border-radius:6px;box-sizing:border-box;">
                                </div>
                                <div>
                                    <label style="font-size:12px;font-weight:bold;">Partenaire / Assurance *</label>
                                    <input type="text" id="dp-disp-partner" value="Allianz Assistance" required style="width:100%;padding:7px;border:1px solid #cbd5e1;border-radius:6px;box-sizing:border-box;">
                                </div>
                            </div>

                            <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-bottom:8px;">
                                <div>
                                    <label style="font-size:12px;font-weight:bold;">Date (jj/mm/aaaa) *</label>
                                    <input type="text" id="dp-disp-date" placeholder="jj/mm/aaaa" maxlength="10" required
                                           style="width:100%;padding:7px;border:1px solid #cbd5e1;border-radius:6px;font-family:monospace;box-sizing:border-box;">
                                </div>
                                <div>
                                    <label style="font-size:12px;font-weight:bold;">Heure (hh:mm) *</label>
                                    <input type="text" id="dp-disp-time" placeholder="14:30" maxlength="5" required
                                           style="width:100%;padding:7px;border:1px solid #cbd5e1;border-radius:6px;font-family:monospace;box-sizing:border-box;">
                                </div>
                            </div>

                            <div style="display:grid;grid-template-columns:2fr 1fr;gap:8px;margin-bottom:8px;">
                                <div>
                                    <label style="font-size:12px;font-weight:bold;">Hôtel *</label>
                                    <input type="text" id="dp-disp-hotel" list="dp-hotels-datalist" required style="width:100%;padding:7px;border:1px solid #cbd5e1;border-radius:6px;box-sizing:border-box;">
                                    <datalist id="dp-hotels-datalist"></datalist>
                                </div>
                                <div>
                                    <label style="font-size:12px;font-weight:bold;">Chambre *</label>
                                    <input type="text" id="dp-disp-room" required style="width:100%;padding:7px;border:1px solid #cbd5e1;border-radius:6px;box-sizing:border-box;">
                                </div>
                            </div>

                            <input type="hidden" id="dp-disp-lat">
                            <input type="hidden" id="dp-disp-lng">

                            <div style="margin-bottom:8px;">
                                <label style="font-size:12px;font-weight:bold;">Type de Prise en Charge</label>
                                <select id="dp-disp-coverage" style="width:100%;padding:7px;border:1px solid #cbd5e1;border-radius:6px;">
                                    <option value="Prise en charge">Prise en charge</option>
                                    <option value="Avec Franchise">Avec Franchise</option>
                                    <option value="Payant">Payant</option>
                                </select>
                            </div>

                            <div style="margin-bottom:14px;">
                                <label style="font-size:12px;font-weight:bold;">Médecin Assigné (Proximité GPS)</label>
                                <select id="dp-disp-doctor" required style="width:100%;padding:7px;border:1px solid #cbd5e1;border-radius:6px;background:#f8fafc;">
                                    <option value="dr_default" data-name="Médecin de Garde">🟢 Médecin de Garde (Par défaut)</option>
                                </select>
                            </div>

                            <button type="submit" style="width:100%;padding:11px;background:#2563eb;color:#fff;border:none;border-radius:6px;font-weight:bold;cursor:pointer;">
                                📡 Dispatcher la Mission
                            </button>
                        </form>
                    </div>

                    <!-- BLOC EXPORT BILAN CONSOLIDÉ -->
                    <div style="border-top:2px solid #e2e8f0;padding-top:12px;margin-top:16px;">
                        <h4 style="margin:0 0 8px 0;color:#0f172a;font-size:14px;">📊 Bilan Comptable Consolidé</h4>
                        <div style="display:grid;grid-template-columns:1fr 1fr;gap:6px;margin-bottom:8px;">
                            <input type="text" id="dp-bilan-start" placeholder="Début jj/mm/aaaa" maxlength="10" style="padding:6px;border:1px solid #cbd5e1;border-radius:4px;font-family:monospace;font-size:12px;">
                            <input type="text" id="dp-bilan-end"   placeholder="Fin jj/mm/aaaa"   maxlength="10" style="padding:6px;border:1px solid #cbd5e1;border-radius:4px;font-family:monospace;font-size:12px;">
                        </div>
                        <div style="display:grid;grid-template-columns:1fr 1fr;gap:6px;margin-bottom:8px;">
                            <select id="dp-bilan-doctor" style="padding:6px;border:1px solid #cbd5e1;border-radius:4px;font-size:12px;">
                                <option value="ALL">Tous médecins</option>
                            </select>
                            <select id="dp-bilan-paid" style="padding:6px;border:1px solid #cbd5e1;border-radius:4px;font-size:12px;">
                                <option value="ALL">Total (Tous)</option>
                                <option value="PAID">Payé</option>
                                <option value="UNPAID">Non payé</option>
                            </select>
                        </div>
                        <div style="display:grid;grid-template-columns:1fr 1fr;gap:6px;">
                            <button type="button" id="dp-btn-export-pdf" style="padding:8px;background:#dc2626;color:#fff;border:none;border-radius:4px;font-weight:bold;cursor:pointer;font-size:12px;">📕 Bilan PDF</button>
                            <button type="button" id="dp-btn-export-csv" style="padding:8px;background:#0f766e;color:#fff;border:none;border-radius:4px;font-weight:bold;cursor:pointer;font-size:12px;">📊 Bilan CSV</button>
                        </div>
                    </div>
                </div>

                <!-- COLONNE DROITE : CARTE TEMPS RÉEL + TABLEAU DE SUPERVISION -->
                <div style="display:grid;grid-template-rows:42% 58%;gap:14px;overflow:hidden;">
                    <div id="dp-cockpit-map" style="background:#cbd5e1;border-radius:10px;box-shadow:0 2px 8px rgba(0,0,0,0.08);"></div>

                    <div style="background:#fff;border-radius:10px;padding:14px;box-shadow:0 2px 8px rgba(0,0,0,0.08);overflow-y:auto;">
                        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:10px;">
                            <h3 style="margin:0;font-size:15px;color:#0f172a;">📋 Supervision Temps Réel des Consultations</h3>
                            <span id="dp-live-counter" style="background:#dcfce7;color:#166534;padding:4px 10px;border-radius:20px;font-size:12px;font-weight:bold;">0 active(s)</span>
                        </div>
                        <table style="width:100%;border-collapse:collapse;font-size:12px;">
                            <thead>
                                <tr style="background:#f1f5f9;text-align:left;border-bottom:2px solid #cbd5e1;">
                                    <th style="padding:8px;">Statut</th>
                                    <th style="padding:8px;">Date / Heure</th>
                                    <th style="padding:8px;">Patient &amp; Dossier</th>
                                    <th style="padding:8px;">Hôtel &amp; Ch.</th>
                                    <th style="padding:8px;">Médecin</th>
                                    <th style="padding:8px;">Honoraires &amp; Actes</th>
                                    <th style="padding:8px;">Actions</th>
                                </tr>
                            </thead>
                            <tbody id="dp-cockpit-tbody"></tbody>
                        </table>
                    </div>
                </div>
            `;

            document.body.appendChild(container);

            // Branchement des masques de dates manuelles jj/mm/aaaa
            ['dp-disp-date', 'dp-bilan-start', 'dp-bilan-end'].forEach(id => {
                const el = document.getElementById(id);
                if (el) el.addEventListener('input', () => DateValidator.applyMask(el));
            });

            // Remplissage de la date du jour par défaut
            const dateInput = document.getElementById('dp-disp-date');
            if (dateInput) dateInput.value = DateValidator.todayFormatted();

            document.getElementById('dp-disp-hotel').addEventListener('change', (e) => this.onHotelSelect(e.target.value));
            document.getElementById('dp-dispatch-form').addEventListener('submit', (e) => this.createMission(e));
            document.getElementById('dp-btn-export-pdf').addEventListener('click', () => accountingConsolidator.exportPDF());
            document.getElementById('dp-btn-export-csv').addEventListener('click', () => accountingConsolidator.exportCSV());
        },

        initMap() {
            if (this.map) return;
            this.map = window.L.map('dp-cockpit-map').setView([35.5047, 11.0622], 12);
            window.L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
                attribution: '© OpenStreetMap contributors'
            }).addTo(this.map);
        },

        populateHotelsDatalist() {
            const dl = document.getElementById('dp-hotels-datalist');
            if (!dl) return;
            dl.innerHTML = (this.hotelsDb || []).map(h => `<option value="${h.name}">`).join('');
        },

        onHotelSelect(hotelName) {
            const found = (this.hotelsDb || []).find(h => h.name && h.name.toLowerCase() === hotelName.toLowerCase());
            if (found && found.lat && found.lng) {
                document.getElementById('dp-disp-lat').value = found.lat;
                document.getElementById('dp-disp-lng').value = found.lng;
                if (this.map) this.map.setView([found.lat, found.lng], 14);
                this.refreshDoctorSelect(found.lat, found.lng);
            }
        },

        getDistanceKm(lat1, lon1, lat2, lon2) {
            if (!lat1 || !lon1 || !lat2 || !lon2) return 9999;
            const R    = 6371;
            const dLat = (lat2 - lat1) * Math.PI / 180;
            const dLon = (lon2 - lon1) * Math.PI / 180;
            const a    = Math.sin(dLat / 2) ** 2 +
                         Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
                         Math.sin(dLon / 2) ** 2;
            return (R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))).toFixed(1);
        },

        listenToDoctorsGPS() {
            if (!window.db) return;
            window.db.collection('doctors_telemetry').onSnapshot(snap => {
                snap.docChanges().forEach(change => {
                    const d = change.doc.data();
                    this.doctorsTelemetry[d.doctorId] = d;
                    if (d.lat && d.lng && this.map) {
                        if (this.doctorMarkers[d.doctorId]) {
                            this.doctorMarkers[d.doctorId].setLatLng([d.lat, d.lng]);
                        } else {
                            this.doctorMarkers[d.doctorId] = window.L.marker([d.lat, d.lng])
                                .addTo(this.map)
                                .bindPopup(`<b>👨‍⚕️ ${d.name}</b><br>Statut : ${d.status || 'Disponible'}`);
                        }
                    }
                });
                const hLat = parseFloat(document.getElementById('dp-disp-lat')?.value);
                const hLng = parseFloat(document.getElementById('dp-disp-lng')?.value);
                this.refreshDoctorSelect(hLat, hLng);
            });
        },

        refreshDoctorSelect(hotelLat, hotelLng) {
            const select      = document.getElementById('dp-disp-doctor');
            const bilanSelect = document.getElementById('dp-bilan-doctor');
            if (!select) return;

            const docs = Object.values(this.doctorsTelemetry).map(d => ({
                ...d,
                distance: (hotelLat && hotelLng) ? this.getDistanceKm(hotelLat, hotelLng, d.lat, d.lng) : null
            }));
            docs.sort((a, b) => (parseFloat(a.distance) || 9999) - (parseFloat(b.distance) || 9999));

            if (docs.length > 0) {
                select.innerHTML = docs.map(d => {
                    const distTxt = (d.distance && d.distance < 9000) ? ` (${d.distance} km)` : '';
                    const icon    = d.isAvailable ? '🟢' : '🟠';
                    return `<option value="${d.doctorId}" data-name="${d.name}">${icon} ${d.name}${distTxt}</option>`;
                }).join('');

                if (bilanSelect) {
                    bilanSelect.innerHTML = `<option value="ALL">Tous médecins</option>` +
                        docs.map(d => `<option value="${d.doctorId}">${d.name}</option>`).join('');
                }
            }
        },

        async createMission(e) {
            e.preventDefault();
            const dateVal = document.getElementById('dp-disp-date').value.trim();
            if (!DateValidator.isValid(dateVal)) {
                alert("Erreur : La date doit obligatoirement être saisie au format jj/mm/aaaa."); return;
            }

            const docSelect  = document.getElementById('dp-disp-doctor');
            const doctorId   = docSelect.value || 'dr_default';
            const doctorName = docSelect.options[docSelect.selectedIndex]?.getAttribute('data-name') || 'Médecin';
            const missionId  = `mission_${Date.now()}`;

            const packet = {
                schemaVersion: 2,
                id:         missionId,
                doctorId:   doctorId,
                doctorName: doctorName,
                status:     'dispatched',
                timestamps: { dispatchedAt: Date.now() },
                adminData: {
                    name:       document.getElementById('dp-disp-name').value.trim(),
                    numDossier: document.getElementById('dp-disp-dossier').value.trim(),
                    date:       dateVal,
                    time:       document.getElementById('dp-disp-time').value.trim(),
                    hotel:      document.getElementById('dp-disp-hotel').value.trim(),
                    room:       document.getElementById('dp-disp-room').value.trim(),
                    hotelLat:   parseFloat(document.getElementById('dp-disp-lat').value) || null,
                    hotelLng:   parseFloat(document.getElementById('dp-disp-lng').value) || null,
                    coverage:   document.getElementById('dp-disp-coverage').value,
                    partner:    document.getElementById('dp-disp-partner').value.trim(),
                    injections: false, sutures: false, soinsLocaux: false,
                    fee: "0.000", tva: "7", paid: false, hasScans: false, hasGdp: false
                },
                medicalPayloadEncrypted: null,
                updatedAt: Date.now(),
                deleted:   false
            };

            if (window.db) {
                await window.db.collection('consultations').doc(missionId).set(packet);
                e.target.reset();
                document.getElementById('dp-disp-date').value = DateValidator.todayFormatted();
            }
        },

        listenToConsultations() {
            if (!window.db) return;
            window.db.collection('consultations')
                .where('deleted', '==', false)
                .onSnapshot(async (snap) => {
                    const list = [];
                    for (const doc of snap.docs) {
                        const unpacked = await hybridStorageEngine.unpackConsultation(doc.data(), null, 'insurance_operator');
                        if (unpacked) list.push(unpacked);
                    }
                    list.sort((a, b) => (b.updatedAt || 0) - (a.updatedAt || 0));
                    this.cachedConsultations = list;
                    this.renderTable(list);
                });
        },

        renderTable(list) {
            const tbody = document.getElementById('dp-cockpit-tbody');
            if (!tbody) return;

            const activeCount = list.filter(v => !['completed', 'closed_paid'].includes(v.status)).length;
            const counterEl   = document.getElementById('dp-live-counter');
            if (counterEl) counterEl.textContent = `${activeCount} mission(s) en cours`;

            const badges = {
                dispatched:  '<span style="background:#fef3c7;color:#92400e;padding:3px 7px;border-radius:10px;font-weight:bold;">📨 Dispatchée</span>',
                en_route:    '<span style="background:#dbeafe;color:#1e40af;padding:3px 7px;border-radius:10px;font-weight:bold;">🚗 En route</span>',
                on_site:     '<span style="background:#f3e8ff;color:#6b21a8;padding:3px 7px;border-radius:10px;font-weight:bold;">🏨 Sur place</span>',
                in_progress: '<span style="background:#fce7f3;color:#9d174d;padding:3px 7px;border-radius:10px;font-weight:bold;">🩺 En examen</span>',
                completed:   '<span style="background:#dcfce7;color:#166534;padding:3px 7px;border-radius:10px;font-weight:bold;">✅ Terminée</span>',
                closed_paid: '<span style="background:#f1f5f9;color:#475569;padding:3px 7px;border-radius:10px;font-weight:bold;">🔒 Réglée</span>'
            };

            tbody.innerHTML = list.map(v => `
                <tr style="border-bottom:1px solid #e2e8f0;">
                    <td style="padding:8px;">${badges[v.status] || v.status}</td>
                    <td style="padding:8px;font-family:monospace;">${v.date || '-'}<br><small>${v.time || ''}</small></td>
                    <td style="padding:8px;"><b>${v.name || '-'}</b><br><small style="color:#64748b;">N° ${v.numDossier || '-'}</small></td>
                    <td style="padding:8px;">${v.hotel || '-'}<br><small>Ch. ${v.room || '-'}</small></td>
                    <td style="padding:8px;">${v.doctorName || v.doctorId || '-'}</td>
                    <td style="padding:8px;"><b>${v.fee || '0.000'} DT</b><br><small>${v.partner || '-'}</small></td>
                    <td style="padding:8px;">
                        ${v.hasGdp
                            ? `<button onclick="window.DocPocketMultiActors.insuranceCockpit.viewGdp('${v.id}','${v.doctorId}')" style="padding:4px 8px;background:#0284c7;color:#fff;border:none;border-radius:4px;cursor:pointer;font-size:11px;margin-right:4px;">📄 GDP</button>`
                            : ''}
                        ${!v.paid
                            ? `<button onclick="window.DocPocketMultiActors.insuranceCockpit.markPaid('${v.id}')" style="padding:4px 8px;background:#16a34a;color:#fff;border:none;border-radius:4px;cursor:pointer;font-size:11px;">✔️ Régler</button>`
                            : '<span style="color:#16a34a;font-weight:bold;">✅ Payé</span>'}
                    </td>
                </tr>
            `).join('');
        },

        async viewGdp(visitId, doctorId) {
            try {
                const b64 = await gdpRelayEngine.fetchAndAssembleGdp(visitId, doctorId);
                const win = window.open("", "_blank", "width=800,height=600");
                win.document.write(`<body style="margin:0;display:flex;justify-content:center;align-items:center;background:#0f172a;"><img src="${b64}" style="max-width:100%;max-height:100vh;"/></body>`);
            } catch (e) {
                if (e.message === "PULL_REQUESTED") {
                    alert("Requête envoyée à l'appareil du médecin. Le scan GDP sera disponible dans quelques secondes.");
                } else {
                    alert("Erreur GDP : " + e.message);
                }
            }
        },

        async markPaid(visitId) {
            if (!window.db) return;
            await window.db.collection('consultations').doc(String(visitId)).update({
                status:           'closed_paid',
                'adminData.paid': true,
                updatedAt:        Date.now()
            });
        }
    };

    // ========================================================================
    // 6. AUTO-INSTALLATEUR SUR L'OBJET GLOBAL `app` DE DOCPOCKET PRO
    // ========================================================================
    const DocPocketMultiActors = {
        DateValidator,
        hybridStorageEngine,
        gdpRelayEngine,
        doctorMissionManager,
        insuranceCockpit,
        accountingConsolidator,

        install(appInstance, options = {}) {
            if (!appInstance) {
                console.warn("[DocPocketMultiActors] Objet global `app` introuvable."); return;
            }

            const doctorId   = options.doctorId   || appInstance.cabinetId           || 'dr_ben_khalifa';
            const doctorName = options.doctorName  || appInstance.settings?.doctorName || 'Dr Hamed Ben Khalifa';

            // 1. Démarrage des écouteurs temps réel côté Médecin
            doctorMissionManager.init(doctorId, doctorName);
            gdpRelayEngine.initDoctorMediaRequestListener(doctorId);

            // 2. Ajout du bouton d'ouverture du Cockpit Assurance dans l'interface
            this.injectCockpitLauncherButton(appInstance);

            console.log(`✅ [DocPocketMultiActors] Architecture Multi-Acteurs activée pour ${doctorName} (${doctorId})`);
        },

        injectCockpitLauncherButton(appInstance) {
            if (document.getElementById('dp-open-cockpit-btn')) return;
            const btn = document.createElement('button');
            btn.id            = 'dp-open-cockpit-btn';
            btn.innerHTML     = '🛰️ Cockpit Assurance';
            btn.style.cssText = 'position:fixed;bottom:16px;right:16px;background:#0f172a;color:#fff;border:2px solid #38bdf8;padding:10px 16px;border-radius:30px;font-weight:bold;cursor:pointer;box-shadow:0 4px 12px rgba(0,0,0,0.3);z-index:9990;font-family:system-ui,sans-serif;';
            btn.onclick = () => {
                const hotels = (appInstance && appInstance.hotelsDb)
                    ? appInstance.hotelsDb
                    : JSON.parse(localStorage.getItem('docpocket_hotels_db') || '[]');
                insuranceCockpit.openCockpit(hotels);
            };
            document.body.appendChild(btn);
        }
    };

    // ── Exposition globale ────────────────────────────────────────────────────
    window.DocPocketMultiActors = DocPocketMultiActors;

})(window);
