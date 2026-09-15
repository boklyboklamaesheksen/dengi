import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../l10n/app_localizations.dart';
import '../widgets/glass_card.dart';
import '../widgets/glass_top_bar.dart';
import '../widgets/halo_field.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.base,
      body: HaloField(
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Row(
                  children: <Widget>[
                    GlassIconButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      onTap: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      l10n.privacyPolicy,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: GlassCard(
                    borderRadius: AppRadii.chunk,
                    // Right padding is slim so the scrollbar can hug the
                    // card's inner wall; the text regains its breathing
                    // room via the inner Padding below.
                    padding: const EdgeInsets.fromLTRB(20, 18, 4, 20),
                    child: RawScrollbar(
                      thumbColor:
                          Colors.white.withValues(alpha: 0.40),
                      thickness: 3,
                      radius: const Radius.circular(2),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(right: 16),
                        child: Text(
                          l10n.privacyPolicyContent,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            height: 1.65,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
