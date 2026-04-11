const fs = require('fs');
const http = require('http');

const html = fs.readFileSync('C:/dcfg/tmp/v4_test_template.html', 'utf-8');
const data = JSON.stringify({ html });

const req = http.request({
  hostname: 'localhost',
  port: 7071,
  path: '/api/html-to-pdf',
  method: 'POST',
  headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data) }
}, (res) => {
  const chunks = [];
  res.on('data', c => chunks.push(c));
  res.on('end', () => {
    if (res.statusCode !== 200) {
      console.error(`HTTP ${res.statusCode}: ${Buffer.concat(chunks).toString()}`);
      return;
    }
    const pdf = Buffer.concat(chunks);
    fs.writeFileSync('C:/dcfg/tmp/v4_function_test.pdf', pdf);
    console.log(`PDF saved: ${pdf.length} bytes → C:/dcfg/tmp/v4_function_test.pdf`);
  });
});

req.on('error', (err) => console.error('Connection error:', err.message));
req.write(data);
req.end();
