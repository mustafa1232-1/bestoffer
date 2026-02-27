String orderStatusLabel(String status) {
  switch (status) {
    case 'pending':
      return '\u0642\u064a\u062f \u0627\u0644\u0627\u0646\u062a\u0638\u0627\u0631';
    case 'preparing':
      return '\u0642\u064a\u062f \u0627\u0644\u062a\u062d\u0636\u064a\u0631';
    case 'ready_for_delivery':
      return '\u062c\u0627\u0647\u0632 \u0644\u0644\u062a\u0648\u0635\u064a\u0644';
    case 'on_the_way':
      return '\u0641\u064a \u0627\u0644\u0637\u0631\u064a\u0642';
    case 'delivered':
      return '\u062a\u0645 \u0627\u0644\u062a\u0633\u0644\u064a\u0645';
    case 'cancelled':
      return '\u0645\u0644\u063a\u064a';
    default:
      return status;
  }
}
