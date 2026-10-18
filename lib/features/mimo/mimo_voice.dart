/// Mimo speaks with a lisp: every "س" comes out as "ث" (مسلكي → مثلكي).
/// English gets the same treatment ("s" → "th").
String mimoLisp(String text) => text
    .replaceAll('س', 'ث')
    .replaceAll(RegExp(r's(?=[a-z])'), 'th')
    .replaceAll('S', 'Th');
