const JSZip = require("jszip");
const fs = require("fs");

async function fixHighlightIssues(file) {
  const buf = fs.readFileSync(file);
  const zip = await JSZip.loadAsync(buf);
  let xml = await zip.files["word/document.xml"].async("string");
  let fixes = 0;

  // Fix 1: Remove yellow highlight from empty/whitespace-only runs
  xml = xml.replace(/<w:r[\s>][\s\S]*?<\/w:r>/g, function(fullRun) {
    if (fullRun.indexOf('w:val="yellow"') === -1) return fullRun;
    var tMatches = fullRun.match(/<w:t[^>]*>([\s\S]*?)<\/w:t>/g) || [];
    var text = tMatches.map(function(t) {
      var m = t.match(/<w:t[^>]*>([\s\S]*?)<\/w:t>/);
      return m ? m[1] : "";
    }).join("");
    if (text.trim() === "") {
      fixes++;
      return fullRun.replace(/<w:highlight\s+w:val="yellow"\s*\/>/g, "");
    }
    return fullRun;
  });

  // Fix 2: Clean "_ Decades Title __" -> "Decades Title"
  xml = xml.replace(/<w:r[\s>][\s\S]*?<\/w:r>/g, function(fullRun) {
    if (fullRun.indexOf('w:val="yellow"') === -1) return fullRun;
    if (fullRun.indexOf("_ Decades Title __") !== -1) {
      fixes++;
      return fullRun.replace(/_ Decades Title __/, "Decades Title");
    }
    return fullRun;
  });

  // Fix 3: Fix "Vendor Signature\" (trailing backslash in yellow tag)
  xml = xml.replace(/<w:r[\s>][\s\S]*?<\/w:r>/g, function(fullRun) {
    if (fullRun.indexOf('w:val="yellow"') === -1) return fullRun;
    if (fullRun.indexOf("Vendor Signature\\") !== -1) {
      fixes++;
      return fullRun.replace("Vendor Signature\\", "Vendor Signature");
    }
    return fullRun;
  });

  // Fix 4: Fix "\Decades_Signature\ _" yellow tag -> "Decades Signature"
  xml = xml.replace(/<w:r[\s>][\s\S]*?<\/w:r>/g, function(fullRun) {
    if (fullRun.indexOf('w:val="yellow"') === -1) return fullRun;
    if (fullRun.indexOf("\\Decades_Signature\\") !== -1) {
      fixes++;
      var cleaned = fullRun.replace(/\\Decades_Signature\\\s*_?/, "Decades Signature");
      return cleaned;
    }
    return fullRun;
  });

  if (fixes > 0) {
    zip.file("word/document.xml", xml, { createFolders: false });
    var out = await zip.generateAsync({ type: "nodebuffer", compression: "DEFLATE" });
    fs.writeFileSync(file, out);
  }
  return fixes;
}

(async () => {
  var dir = "C:/DCFG/Templates/for-reupload/";
  var files = fs.readdirSync(dir).filter(function(f) { return f.endsWith(".docx"); });
  for (var f of files) {
    var n = await fixHighlightIssues(dir + f);
    console.log(f + ": " + n + " fixes");
  }
})();
