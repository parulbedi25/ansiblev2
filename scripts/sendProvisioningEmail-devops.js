const nodemailer = require("nodemailer");
const yargs = require("yargs/yargs");
const { hideBin } = require("yargs/helpers");

const argv = yargs(hideBin(process.argv)).options({
  smtpServer: { type: "string", demandOption: true },
  smtpUser: { type: "string", demandOption: true },
  smtpPassword: { type: "string", demandOption: true },
  smtpPort: { type: "string", demandOption: true },

  senderName: { type: "string", demandOption: true },
  senderEmail: { type: "string", demandOption: true },
  receiverEmail: { type: "string", demandOption: true },

  projectName: { type: "string", demandOption: true },
  projectType: { type: "string", demandOption: true },
  ipAddress: { type: "string", demandOption: true },
  osType: { type: "string", demandOption: true },
  agentName: { type: "string", demandOption: true },
  executionTime: { type: "string", demandOption: true },


  status: { type: "string", demandOption: true },
  runUrl: { type: "string", demandOption: true }
}).argv;

(async function sendProvisioningEmail() {
  try {
    const transporter = nodemailer.createTransport({
      host: argv.smtpServer,
      port: parseInt(argv.smtpPort),
      secure: argv.smtpPort === "465",
      requireTLS: argv.smtpPort === "587",
      tls: {
        minVersion: "TLSv1.2",
        rejectUnauthorized: false,
      },
      auth: {
        user: argv.smtpUser,
        pass: argv.smtpPassword,
      },
    });

    await transporter.verify();
    console.log("SMTP connection verified");

    const status = argv.status.toLowerCase();
    const statusEmoji = status === "success" ? "✅" : "❌";
    const statusColor = status === "success" ? "#28a745" : "#d73a49";
    const subjectStatus = status.toUpperCase();

    const executionDate = new Date().toLocaleString("en-GB", {
      timeZone: "Asia/Kolkata"
    });

    const recipients = argv.receiverEmail
      .split(",")
      .map(e => e.trim())
      .filter(e => e.length > 0);

    const html = `
<!DOCTYPE html>
<html>
<head>
  <style>
    body {
      font-family: Arial, sans-serif;
      background-color: #f4f6f9;
      padding: 20px;
    }
    .container {
      background: #ffffff;
      border-radius: 8px;
      padding: 25px;
      max-width: 650px;
      margin: auto;
      box-shadow: 0 4px 12px rgba(0,0,0,0.1);
    }
    h2 {
      color: ${statusColor};
    }
    table {
      width: 100%;
      border-collapse: collapse;
      margin-top: 15px;
    }
    th, td {
      padding: 10px;
      border: 1px solid #e0e0e0;
      text-align: left;
    }
    th {
      background-color: #f5f7fa;
      width: 40%;
    }
    .status {
      color: ${statusColor};
      font-weight: bold;
    }
    .footer {
      margin-top: 25px;
      font-size: 0.9em;
      color: #666;
    }
  </style>
</head>
<body>
  <div class="container">
    <h2>QASIP Instance Provisioning ${statusEmoji} ${subjectStatus}</h2>

    <p>Hello Team,</p>

    <p>The QASIP instance provisioning pipeline has completed. Below are the details:</p>

    <table>
      <tr>
        <th>Project Name</th>
        <td>${argv.projectName}</td>
      </tr>
      <tr>
        <th>Project Type</th>
        <td>${argv.projectType}</td>
      </tr>
      <tr>
        <th>QASIP Machine IP Address</th>
        <td>${argv.ipAddress}</td>
      </tr>
      <tr>
        <th>Operating System</th>
        <td>${argv.osType}</td>
      </tr>
      <tr>
        <th>QASIP Agent Name</th>
        <td>${argv.agentName}</td>
      </tr>
      <tr>
        <th>Pipeline Status</th>
        <td class="status">${subjectStatus}</td>
      </tr>
      <tr>
        <th>Execution Time</th>
        <td>${executionDate}</td>
      </tr>
      <tr>
        <th>Pipeline Duration</th>
        <td>${argv.executionTime}</td>
      </tr>
      <tr>
        <th>Pipeline URL</th>
        <td><a href="${argv.runUrl}">View Build Logs</a></td>
      </tr>
    </table>

    <div class="footer">
      Regards,<br/>
      DevOps Team
    </div>
  </div>
</body>
</html>
`;

    await transporter.sendMail({
      from: `${argv.senderName} <${argv.senderEmail}>`,
      to: recipients,
      subject: `QASIP Instance Provisioning ${subjectStatus} | ${argv.agentName}`,
      html: html,
    });

    console.log("✅ Provisioning email sent successfully");

  } catch (error) {
    console.error("❌ Error sending email:", error);
    process.exit(1);
  }
})();