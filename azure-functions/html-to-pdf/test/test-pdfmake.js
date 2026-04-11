// Test pdfmake PDF generation locally (no Azure Function needed)
const PdfPrinter = require('pdfmake');
const fs = require('fs');

const fonts = {
  TimesRoman: {
    normal: 'Times-Roman',
    bold: 'Times-Bold',
    italics: 'Times-Italic',
    bolditalics: 'Times-BoldItalic'
  }
};

const printer = new PdfPrinter(fonts);

// Bancroft Blanket Work Order — pdfmake document definition
const docDefinition = {
  pageSize: 'LETTER',
  pageMargins: [54, 54, 54, 72], // 0.75in all sides, 1in bottom
  defaultStyle: { font: 'TimesRoman', fontSize: 11, lineHeight: 1.35 },

  content: [
    { text: 'Work Order', style: 'title' },
    { text: '' }, // spacer

    { text: [
      { text: '    ' }, // indent
      'This work order ("Work order") dated ',
      { text: '04/06/2026', bold: true },
      ', supplements the Master Services Agreement between the below listed Vendor and Decades Construction Group, Inc. ("Contractor") dated ',
      { text: '01/15/2025', bold: true },
      ' (the "Contract") and is governed by and subject to the terms and conditions of the contract.'
    ], margin: [0, 0, 0, 6] },

    { text: [
      { text: '    ' },
      'Capitalized terms not otherwise defined shall have the meanings ascribed to them in the Contract. The parties hereby agree as follows:'
    ], margin: [0, 0, 0, 6] },

    { text: [
      { text: '1. ', bold: true },
      { text: 'Vendor', bold: true },
      ': ABC Plumbing Services, LLC ("Vendor") shall provide the following Work: Scope of work to be determined on an as needed basis and shall not commence without written approval via email including an assigned Project/Cost Code. If further work and parts/materials are needed to complete services or correct issues, vendor shall provide in proposal or email the estimated additional costs, to include parts, material, and labor for approval. In the event of work being needed after hours, on weekends or Holidays, proceed on verbal approval, with the email authorization being provided by the Decades Representative on the next business day.'
    ], margin: [0, 0, 0, 6] },

    { text: [
      { text: '2. ', bold: true },
      'The Work shall be performed at any location(s) as directed and as applicable to approved proposals.'
    ], margin: [0, 0, 0, 6] },

    { text: [
      { text: '3. ', bold: true },
      'This work order shall become effective upon being fully executed and will cover work as awarded per item No. 1 above. This work order shall terminate upon written notification of either party.'
    ], margin: [0, 0, 0, 6] },

    { text: [
      { text: '4. ', bold: true },
      'The fee for the Work shall be per approved proposals or approved billable rates & maximum material markups on an as needed basis.'
    ], margin: [0, 0, 0, 6] },

    { text: [
      { text: '5. ', bold: true },
      "Contractor's and Vendor's primary point of contact for all matters pertaining to Contractor's and Vendor's responsibilities under this Work Order are the individuals listed below. Either party may change its primary point of contact at any time without notice to the other party."
    ], margin: [0, 0, 0, 6] },

    // Contact block
    { text: [
      { text: 'Contractor', bold: true },
      ' Primary Contract Contact: Joseph Cameron, Project Manager, jcameron@decades-cg.com'
    ], margin: [36, 0, 0, 2] },
    { text: [
      { text: 'Vendor', bold: true },
      ' Primary Contract Contact: Michael Rodriguez, Owner, mrodriguez@abcplumbing.com'
    ], margin: [36, 0, 0, 6] },

    { text: [
      { text: '5. ', bold: true },
      { text: 'Billing Procedures:', bold: true, decoration: 'underline' },
      ' All invoices shall reference the forthcoming Project/Cost Code(s), which will be provided when approval to proceed is sent via email. Submit invoices to DecadesAP@decades-cg.com per the terms of this agreement.'
    ], margin: [0, 0, 0, 6] },

    { text: [
      { text: '6. ', bold: true },
      { text: 'Payment Terms:', bold: true, decoration: 'underline' },
      ' Invoices will be subject to payment terms as defined by the fully executed Master Services Agreement (MSA).'
    ], margin: [0, 0, 0, 18] },

    { text: 'IN WITNESS WHEREOF, each party\'s duly authorized representative has executed this Work Order as of the date and year first mentioned above.',
      bold: true, alignment: 'center', margin: [0, 0, 0, 18] },

    // Signature block - two columns
    {
      columns: [
        {
          width: '48%',
          stack: [
            { text: 'SUBCONTRACTOR', bold: true, alignment: 'center', margin: [0, 0, 0, 6] },
            { text: 'ABC Plumbing Services, LLC', bold: true, margin: [0, 0, 0, 6] },
            { text: 'By:', margin: [0, 12, 0, 0] },
            { canvas: [{ type: 'line', x1: 0, y1: 0, x2: 200, y2: 0, lineWidth: 0.5 }], margin: [0, 18, 0, 2] },
            { text: 'Print Name: Michael Rodriguez', fontSize: 10 },
            { text: 'Title: Owner', fontSize: 10 },
            { text: 'Phone: (215) 555-0234', fontSize: 10 },
            { text: 'Email: mrodriguez@abcplumbing.com', fontSize: 10 },
            { text: 'Address: 456 Industrial Blvd, King of Prussia, PA 19406', fontSize: 10 },
            { text: '', margin: [0, 6, 0, 0] },
            { text: [
              'Date: ',
              { canvas: [{ type: 'line', x1: 0, y1: 0, x2: 120, y2: 0, lineWidth: 0.5 }] }
            ], fontSize: 10 }
          ]
        },
        { width: '4%', text: '' },
        {
          width: '48%',
          stack: [
            { text: 'CONTRACTOR', bold: true, alignment: 'center', margin: [0, 0, 0, 6] },
            { text: 'Decades Construction Group, Inc.', bold: true, margin: [0, 0, 0, 6] },
            { text: 'By:', margin: [0, 12, 0, 0] },
            { canvas: [{ type: 'line', x1: 0, y1: 0, x2: 200, y2: 0, lineWidth: 0.5 }], margin: [0, 18, 0, 2] },
            { text: 'Print Name: Joseph Cameron', fontSize: 10 },
            { text: 'Title: Project Manager', fontSize: 10 },
            { text: 'Phone: (215) 555-0100', fontSize: 10 },
            { text: 'Email: jcameron@decades-cg.com', fontSize: 10 },
            { text: '', margin: [0, 6, 0, 0] },
            { text: [
              'Date: ',
              { canvas: [{ type: 'line', x1: 0, y1: 0, x2: 120, y2: 0, lineWidth: 0.5 }] }
            ], fontSize: 10 }
          ]
        }
      ]
    }
  ],

  styles: {
    title: { fontSize: 11, bold: true, alignment: 'center', margin: [0, 0, 0, 12] }
  }
};

const pdfDoc = printer.createPdfKitDocument(docDefinition);
const chunks = [];
pdfDoc.on('data', c => chunks.push(c));
pdfDoc.on('end', () => {
  const buf = Buffer.concat(chunks);
  fs.writeFileSync('C:/dcfg/tmp/v4_pdfmake_test.pdf', buf);
  console.log(`PDF saved: ${buf.length} bytes → C:/dcfg/tmp/v4_pdfmake_test.pdf`);
});
pdfDoc.end();
