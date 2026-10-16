const nodemailer = require("nodemailer");

function parseArgs(argv) {
  const out = {};
  for (let i = 2; i < argv.length; i++) {
    const token = argv[i];
    if (!token || token.indexOf("--") !== 0) {
      continue;
    }
    const eqIndex = token.indexOf("=");
    if (eqIndex > -1) {
      const key = token.slice(2, eqIndex);
      const val = token.slice(eqIndex + 1);
      out[key] = val;
      continue;
    }
    const key = token.slice(2);
    const next = argv[i + 1];
    if (next && next.indexOf("--") !== 0) {
      out[key] = next;
      i++;
    } else {
      out[key] = "";
    }
  }
  return out;
}

const argv = parseArgs(process.argv);
const required = [
  "smtpServer",
  "smtpUser",
  "smtpPassword",
  "smtpPort",
  "senderName",
  "senderEmail",
  "receiverEmail",
  "pipelineType",
  "projectTargetMachine",
  "projectName",
  "status",
  "executionTime"
];

const missing = required.filter((k) => !argv[k] || String(argv[k]).trim() === "");
if (missing.length) {
  console.error("Missing required args:", missing.join(", "));
  process.exit(1);
}
if (!argv.detailLine) {
  argv.detailLine = "";
}
if (!argv.buildNumber || String(argv.buildNumber).trim() === "") {
  const now = new Date();
  const yyyy = String(now.getFullYear());
  const mm = String(now.getMonth() + 1).padStart(2, "0");
  const dd = String(now.getDate()).padStart(2, "0");
  const hh = String(now.getHours()).padStart(2, "0");
  argv.buildNumber = `${dd}-${mm}-${yyyy}-${hh}-build0`;
}

(async function sendDbPipelineEmail() {
  try {
    const transporter = nodemailer.createTransport({
      host: argv.smtpServer,
      port: parseInt(argv.smtpPort, 10),
      secure: argv.smtpPort === "465",
      requireTLS: argv.smtpPort === "587",
      tls: {
        minVersion: "TLSv1.2",
        rejectUnauthorized: false
      },
      auth: {
        user: argv.smtpUser,
        pass: argv.smtpPassword
      }
    });

    await transporter.verify();

    const status = argv.status.toLowerCase();
    const isSuccess = status === "success";
    const statusLabel = isSuccess ? "SUCCESS" : "FAILURE";
    const statusColor = isSuccess ? "#28a745" : "#d73a49";
    const statusEmoji = isSuccess ? "&#9989;" : "&#10060;";
    const executionDate = new Date().toLocaleString("en-GB", { timeZone: "Asia/Kolkata" });
    const recipients = argv.receiverEmail.split(",").map(e => e.trim()).filter(Boolean);
    const title = argv.pipelineType.toUpperCase();
    const pipelineLabel = argv.pipelineType.charAt(0).toUpperCase() + argv.pipelineType.slice(1).toLowerCase();
    const pipelineSummary = isSuccess
      ? `The database ${pipelineLabel} pipeline has completed successfully.`
      : `The database ${pipelineLabel} pipeline has failed.`;
    const notesRow = argv.detailLine
      ? `<tr><th>Notes</th><td>${argv.detailLine}</td></tr>`
      : "";

    const html = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <style>
    body { font-family: Arial, sans-serif; background-color: #f4f6f9; padding: 20px; }
    .container { background: #ffffff; border-radius: 8px; padding: 25px; max-width: 700px; margin: auto; box-shadow: 0 4px 12px rgba(0,0,0,0.1); }
    h2 { color: ${statusColor}; }
    table { width: 100%; border-collapse: collapse; margin-top: 15px; }
    th, td { padding: 10px; border: 1px solid #e0e0e0; text-align: left; }
    th { background-color: #f5f7fa; width: 36%; }
    .status { color: ${statusColor}; font-weight: bold; }
    .footer { margin-top: 25px; font-size: 0.9em; color: #666; }
  </style>
</head>
<body>
  <div class="container">
    <h2>QASIP DB ${title} ${statusEmoji} ${statusLabel}</h2>
    <p>Hello Team,</p>
    <p>${pipelineSummary}</p>
    <table>
      <tr><th>Pipeline</th><td>${pipelineLabel}</td></tr>
      <tr><th>Project Name</th><td>${argv.projectName}</td></tr>
      <tr><th>Target Machine</th><td>${argv.projectTargetMachine}</td></tr>
      <tr><th>Backup Folder</th><td>${argv.buildNumber}</td></tr>
      <tr><th>Status</th><td class="status">${statusLabel}</td></tr>
      <tr><th>Execution Time (IST)</th><td>${executionDate}</td></tr>
      <tr><th>Pipeline Duration</th><td>${argv.executionTime}</td></tr>
      ${notesRow}
    </table>
    <div class="footer">Regards,<br/>DevOps Team</div>
  </div>
</body>
</html>`;

    await transporter.sendMail({
      from: `${argv.senderName} <${argv.senderEmail}>`,
      to: recipients,
      subject: `QASIP DB ${title} ${statusLabel} | ${argv.projectTargetMachine}`,
      html
    });

    console.log("DB pipeline email sent successfully");
  } catch (error) {
    console.error("Error sending DB pipeline email:", error);
    process.exit(1);
  }
})();
