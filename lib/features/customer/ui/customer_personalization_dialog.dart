import 'package:flutter/material.dart';

class CustomerPersonalizationDialog extends StatefulWidget {
  final Future<void> Function({
    required String audience,
    required String priority,
    required List<String> interests,
  })
  onSubmit;

  const CustomerPersonalizationDialog({super.key, required this.onSubmit});

  @override
  State<CustomerPersonalizationDialog> createState() =>
      _CustomerPersonalizationDialogState();
}

class _CustomerPersonalizationDialogState
    extends State<CustomerPersonalizationDialog> {
  String _audience = 'any';
  String _priority = 'balanced';
  final Set<String> _interests = <String>{'restaurants', 'markets'};
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    await widget.onSubmit(
      audience: _audience,
      priority: _priority,
      interests: _interests.toList(),
    );
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('خل نرتب واجهتك'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _ChatHintBubble(
                text:
                    'أهلاً بيك، جاوبني 3 أسئلة سريعة حتى أرتب الصفحة حسب ذوقك 👌',
              ),
              const SizedBox(height: 10),
              const _SectionTitle('1) تفضّل عروض أكثر على:'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _audienceOptions
                    .map(
                      (option) => ChoiceChip(
                        label: Text(option.label),
                        selected: _audience == option.key,
                        onSelected: (_) =>
                            setState(() => _audience = option.key),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 14),
              const _SectionTitle('2) أولويتك الرئيسية:'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _priorityOptions
                    .map(
                      (option) => ChoiceChip(
                        label: Text(option.label),
                        selected: _priority == option.key,
                        onSelected: (_) =>
                            setState(() => _priority = option.key),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 14),
              const _SectionTitle('3) شنو تحب تشوف أكثر؟'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _interestOptions
                    .map(
                      (option) => FilterChip(
                        label: Text(option.label),
                        selected: _interests.contains(option.key),
                        onSelected: (value) {
                          setState(() {
                            if (value) {
                              _interests.add(option.key);
                            } else {
                              _interests.remove(option.key);
                            }
                          });
                        },
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 8),
              Text(
                'تقدر تغيّر هذي التفضيلات لاحقًا من نفس الواجهة.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            child: const Text('لاحقًا'),
          ),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            label: const Text('اعتماد التخصيص'),
          ),
        ],
      ),
    );
  }
}

class _ChatHintBubble extends StatelessWidget {
  final String text;

  const _ChatHintBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withValues(alpha: 0.08),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Text(text),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _KeyLabel {
  final String key;
  final String label;

  const _KeyLabel(this.key, this.label);
}

const _audienceOptions = <_KeyLabel>[
  _KeyLabel('women', 'نسائي'),
  _KeyLabel('men', 'رجالي'),
  _KeyLabel('family', 'عائلي'),
  _KeyLabel('mixed', 'متنوع'),
  _KeyLabel('any', 'أي شيء مفيد'),
];

const _priorityOptions = <_KeyLabel>[
  _KeyLabel('offers', 'أقوى عروض'),
  _KeyLabel('price', 'أقل سعر'),
  _KeyLabel('speed', 'أسرع توصيل'),
  _KeyLabel('rating', 'أعلى تقييم'),
  _KeyLabel('balanced', 'متوازن'),
];

const _interestOptions = <_KeyLabel>[
  _KeyLabel('restaurants', 'مطاعم'),
  _KeyLabel('sweets', 'حلويات'),
  _KeyLabel('markets', 'أسواق'),
  _KeyLabel('women_fashion', 'أزياء نسائية'),
  _KeyLabel('men_fashion', 'أزياء رجالية'),
  _KeyLabel('shoes', 'أحذية'),
  _KeyLabel('bags', 'شنط'),
  _KeyLabel('beauty', 'عناية وتجميل'),
  _KeyLabel('electronics', 'كهربائيات'),
  _KeyLabel('home', 'مستلزمات منزل'),
  _KeyLabel('kids', 'أطفال'),
  _KeyLabel('sports', 'رياضة'),
  _KeyLabel('coffee', 'قهوة ومشروبات'),
  _KeyLabel('gifts', 'هدايا'),
];
