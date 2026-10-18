const { app, BrowserWindow } = require('electron');
const path = require('path');
const express = require('express');
const http = require('http');

let server;
let win;

function startServerAndCreateWindow() {
  const expressApp = express();
  const webDir = path.join(__dirname, 'flutter_web');

  // Parse JSON payloads up to 100MB for attached documents / PDFs / images
  expressApp.use(express.json({ limit: '100mb' }));
  expressApp.use(express.urlencoded({ extended: true, limit: '100mb' }));

  // API endpoint for sending email with attachments on macOS via Apple Mail (DocPocket Pro parity)
  expressApp.post('/api/send-mail', async (req, res) => {
    try {
      const { to, subject, bodyText, filesArray } = req.body;
      const os = require('os');
      const fs = require('fs');
      const { exec } = require('child_process');

      if (process.platform === 'darwin') {
        const timestamp = Date.now();
        const tempSubDir = path.join(os.tmpdir(), `ELAA_Mail_${timestamp}`);
        if (!fs.existsSync(tempSubDir)) {
          fs.mkdirSync(tempSubDir, { recursive: true });
        }

        const attachmentPaths = [];
        if (filesArray && Array.isArray(filesArray)) {
          for (const file of filesArray) {
            const safeName = (file.filename || 'document.pdf').replace(/[/\\?%*:|"<>]/g, '_');
            const filePath = path.join(tempSubDir, safeName);
            let buffer = file.isBase64 ? Buffer.from(file.data, 'base64') : Buffer.from(file.data, 'utf8');
            fs.writeFileSync(filePath, buffer);
            attachmentPaths.push(filePath);
          }
        }

        const escapeAppleScript = (str) => {
          return (str || '')
            .replace(/\\/g, '\\\\')
            .replace(/"/g, '\\"');
        };

        const safeSubject = escapeAppleScript(subject);
        const safeBody = (bodyText || '')
          .split('\n')
          .map(line => `"${escapeAppleScript(line)}"`)
          .join(' & return & ');

        let script = `tell application "Mail"\n`;
        script += `    set newMessage to make new outgoing message with properties {subject:"${safeSubject}", content:(${safeBody || '""'}) & return & return, visible:true}\n`;
        script += `    tell newMessage\n`;
        if (to && to.trim().length > 0) {
          script += `        make new to recipient at end of to recipients with properties {address:"${escapeAppleScript(to.trim())}"}\n`;
        }
        if (attachmentPaths.length > 0) {
          script += `        tell content\n`;
          for (const p of attachmentPaths) {
            script += `            make new attachment with properties {file name:"${escapeAppleScript(p)}"} at after the last paragraph\n`;
          }
          script += `        end tell\n`;
        }
        script += `    end tell\n`;
        script += `    activate\n`;
        script += `end tell\n`;

        const scriptFile = path.join(tempSubDir, `send_mail_${timestamp}.scpt`);
        fs.writeFileSync(scriptFile, script, 'utf8');

        exec(`osascript "${scriptFile}"`, (error, stdout, stderr) => {
          try { fs.unlinkSync(scriptFile); } catch (_) {}
          if (error) {
            console.warn("AppleScript Apple Events error, applying fallback:", error.message || stderr);
            // Fallback: Open directory in Finder and open mailto
            exec(`open "${tempSubDir}"`);
            const mailtoUrl = `mailto:${encodeURIComponent(to || '')}?subject=${encodeURIComponent(subject || '')}&body=${encodeURIComponent(bodyText || '')}`;
            exec(`open "${mailtoUrl}"`);
            res.json({
              success: true,
              fallback: true,
              folderPath: tempSubDir,
              message: "Dossier ouvert dans Finder avec pièces jointes et client mail activé.",
              count: attachmentPaths.length
            });
          } else {
            console.log("Apple Mail message created with attachments successfully");
            res.json({ success: true, count: attachmentPaths.length, folderPath: tempSubDir });
          }
        });
      } else {
        res.json({ success: false, error: "Non-macOS platform" });
      }
    } catch (err) {
      console.error("Error in /api/send-mail:", err);
      res.status(500).json({ success: false, error: err.message });
    }
  });

  // Serve static Flutter web files
  expressApp.use(express.static(webDir));

  // Fallback for SPA routing
  expressApp.get('*', (req, res) => {
    res.sendFile(path.join(webDir, 'index.html'));
  });

  server = http.createServer(expressApp);
  const DEFAULT_PORT = 41236;
  server.listen(DEFAULT_PORT, '127.0.0.1', () => {
    const port = server.address().port;
    console.log(`Local Express server running on http://127.0.0.1:${port}`);
    createWindow(`http://127.0.0.1:${port}`);
  }).on('error', (err) => {
    if (err.code === 'EADDRINUSE') {
      server.listen(0, '127.0.0.1', () => {
        const port = server.address().port;
        console.log(`Local Express server running on fallback port http://127.0.0.1:${port}`);
        createWindow(`http://127.0.0.1:${port}`);
      });
    }
  });
}

function createWindow(url) {
  win = new BrowserWindow({
    width: 1280,
    height: 800,
    title: 'ELAA DocPocket Pro Hub Opérateur',
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      webSecurity: true
    }
  });

  win.loadURL(url);

  win.on('closed', () => {
    win = null;
  });
}

app.whenReady().then(() => {
  startServerAndCreateWindow();
});

app.on('window-all-closed', () => {
  if (server) {
    server.close();
  }
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) {
    startServerAndCreateWindow();
  }
});
