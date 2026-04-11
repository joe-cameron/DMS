const PDFDocument = require('pdfkit');
const fs = require('fs');

// Simulate what the Azure Function receives — a "sections" array
// This is the Bancroft Blanket Work Order with sample data substituted

const doc = new PDFDocument({
  size: 'LETTER',
  margins: { top: 54, bottom: 72, left: 54, right: 54 },
});

const stream = fs.createWriteStream('C:/dcfg/tmp/v4_bancroft_pdfkit.pdf');
doc.pipe(stream);

const F = 'Times-Roman';
const FB = 'Times-Bold';
const FI = 'Times-Italic';
const S = 11;
const SM = 10;

// Title
doc.font(FB).fontSize(S).text('Work Order', { align: 'center' });
doc.moveDown();

// Intro paragraph
doc.font(F).fontSize(S)
  .text('This work order ("Work order") dated ', { continued: true, indent: 36 })
  .font(FB).text('04/06/2026', { continued: true })
  .font(F).text(', supplements the Master Services Agreement between the below listed Vendor and Decades Construction Group, Inc. ("Contractor") dated ', { continued: true })
  .font(FB).text('01/15/2025', { continued: true })
  .font(F).text(' (the "Contract") and is governed by and subject to the terms and conditions of the contract.');
doc.moveDown(0.5);

doc.font(F).text('Capitalized terms not otherwise defined shall have the meanings ascribed to them in the Contract. The parties hereby agree as follows:', { indent: 36 });
doc.moveDown(0.5);

// Section 1
doc.font(FB).text('1. ', { continued: true })
  .font(FB).text('Vendor', { continued: true })
  .font(F).text(': ABC Plumbing Services, LLC ("Vendor") shall provide the following Work: Scope of work to be determined on an as needed basis and shall not commence without written approval via email including an assigned Project/Cost Code. If further work and parts/materials are needed to complete services or correct issues, vendor shall provide in proposal or email the estimated additional costs, to include parts, material, and labor for approval. In the event of work being needed after hours, on weekends or Holidays, proceed on verbal approval, with the email authorization being provided by the Decades Representative on the next business day.');
doc.moveDown(0.5);

// Section 2
doc.font(FB).text('2. ', { continued: true })
  .font(F).text('The Work shall be performed at any location(s) as directed and as applicable to approved proposals.');
doc.moveDown(0.5);

// Section 3
doc.font(FB).text('3. ', { continued: true })
  .font(F).text('This work order shall become effective upon being fully executed and will cover work as awarded per item No. 1 above. This work order shall terminate upon written notification of either party.');
doc.moveDown(0.5);

// Section 4
doc.font(FB).text('4. ', { continued: true })
  .font(F).text('The fee for the Work shall be per approved proposals or approved billable rates & maximum material markups on an as needed basis.');
doc.moveDown(0.5);

// Section 5
doc.font(FB).text('5. ', { continued: true })
  .font(F).text("Contractor's and Vendor's primary point of contact for all matters pertaining to Contractor's and Vendor's responsibilities under this Work Order are the individuals listed below. Either party may change its primary point of contact at any time without notice to the other party.");
doc.moveDown(0.5);

// Contact block
doc.font(FB).text('Contractor', { continued: true, indent: 36 })
  .font(F).text(' Primary Contract Contact: Joseph Cameron, Project Manager, jcameron@decades-cg.com');
doc.font(FB).text('Vendor', { continued: true, indent: 36 })
  .font(F).text(' Primary Contract Contact: Michael Rodriguez, Owner, mrodriguez@abcplumbing.com');
doc.moveDown(0.5);

// Section 5 (billing)
doc.font(FB).text('5. ', { continued: true })
  .font(FB).text('Billing Procedures: ', { continued: true, underline: true })
  .font(F).text('All invoices shall reference the forthcoming Project/Cost Code(s), which will be provided when approval to proceed is sent via email. Submit invoices to DecadesAP@decades-cg.com per the terms of this agreement.', { underline: false });
doc.moveDown(0.5);

// Section 6
doc.font(FB).text('6. ', { continued: true })
  .font(FB).text('Payment Terms: ', { continued: true, underline: true })
  .font(F).text('Invoices will be subject to payment terms as defined by the fully executed Master Services Agreement (MSA).', { underline: false });
doc.moveDown(1.5);

// Witness clause
doc.font(FB).text("IN WITNESS WHEREOF, each party's duly authorized representative has executed this Work Order as of the date and year first mentioned above.", { align: 'center' });
doc.moveDown(1.5);

// Signature block - two columns
const sigY = doc.y;
const leftX = doc.page.margins.left;
const colW = (doc.page.width - doc.page.margins.left - doc.page.margins.right - 18) / 2;
const rightX = leftX + colW + 18;

// Left column - SUBCONTRACTOR
doc.font(FB).fontSize(S).text('SUBCONTRACTOR', leftX, sigY, { width: colW, align: 'center' });
doc.font(FB).text('ABC Plumbing Services, LLC', leftX, doc.y, { width: colW });
doc.moveDown(0.5);
doc.font(F).text('By:', leftX, doc.y, { width: colW });
const sigLineY1 = doc.y + 18;
doc.moveTo(leftX, sigLineY1).lineTo(leftX + colW - 20, sigLineY1).lineWidth(0.5).stroke();
doc.fontSize(SM);
doc.text('Print Name: Michael Rodriguez', leftX, sigLineY1 + 4, { width: colW });
doc.text('Title: Owner', leftX, doc.y, { width: colW });
doc.text('Phone: (215) 555-0234', leftX, doc.y, { width: colW });
doc.text('Email: mrodriguez@abcplumbing.com', leftX, doc.y, { width: colW });
doc.text('Address: 456 Industrial Blvd, King of Prussia, PA 19406', leftX, doc.y, { width: colW });
doc.moveDown(0.5);
const dateLineY1 = doc.y;
doc.text('Date: ', leftX, dateLineY1, { width: 30, continued: false });
doc.moveTo(leftX + 32, dateLineY1 + 10).lineTo(leftX + 150, dateLineY1 + 10).lineWidth(0.5).stroke();

// Right column - CONTRACTOR
doc.font(FB).fontSize(S).text('CONTRACTOR', rightX, sigY, { width: colW, align: 'center' });
doc.font(FB).text('Decades Construction Group, Inc.', rightX, doc.y, { width: colW });
doc.moveDown(0.5);
doc.font(F).text('By:', rightX, doc.y, { width: colW });
doc.moveTo(rightX, sigLineY1).lineTo(rightX + colW - 20, sigLineY1).lineWidth(0.5).stroke();
doc.fontSize(SM);
doc.text('Print Name: Joseph Cameron', rightX, sigLineY1 + 4, { width: colW });
doc.text('Title: Project Manager', rightX, doc.y, { width: colW });
doc.text('Phone: (215) 555-0100', rightX, doc.y, { width: colW });
doc.text('Email: jcameron@decades-cg.com', rightX, doc.y, { width: colW });
doc.moveDown(0.5);
const dateLineY2 = doc.y;
doc.text('Date: ', rightX, dateLineY2, { width: 30, continued: false });
doc.moveTo(rightX + 32, dateLineY2 + 10).lineTo(rightX + 150, dateLineY2 + 10).lineWidth(0.5).stroke();

doc.end();

stream.on('finish', () => {
  const size = fs.statSync('C:/dcfg/tmp/v4_bancroft_pdfkit.pdf').size;
  console.log(`Bancroft WO PDF saved: ${size} bytes → C:/dcfg/tmp/v4_bancroft_pdfkit.pdf`);
});
