import 'package:flutter/material.dart';

import 'builtin_themes.dart';
import 'err_theme.dart';

class ThemePickerSheet extends StatelessWidget {
  const ThemePickerSheet({
    super.key,
    required this.activeTheme,
    required this.customThemes,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
    required this.onNew,
  });

  final ErrTheme activeTheme;
  final List<ErrTheme> customThemes;
  final void Function(ErrTheme) onSelect;
  final void Function(ErrTheme) onEdit;
  final void Function(String id) onDelete;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: activeTheme.screenBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: activeTheme.toggleBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  'Choose Theme',
                  style: TextStyle(
                    color: activeTheme.statValue,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: CustomScrollView(
              slivers: [
                _sectionHeader('Built-in', activeTheme),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.55,
                    ),
                    itemCount: builtinThemes.length,
                    itemBuilder: (_, i) {
                      final t = builtinThemes[i];
                      return _ThemeCard(
                        theme: t,
                        isActive: t.id == activeTheme.id,
                        onTap: () => onSelect(t),
                      );
                    },
                  ),
                ),
                _sectionHeader('Custom', activeTheme),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 1.55,
                    ),
                    itemCount: customThemes.length + 1,
                    itemBuilder: (_, i) {
                      if (i == customThemes.length) {
                        return _NewThemeCard(
                          activeTheme: activeTheme,
                          onTap: onNew,
                        );
                      }
                      final t = customThemes[i];
                      return _ThemeCard(
                        theme: t,
                        isActive: t.id == activeTheme.id,
                        onTap: () => onSelect(t),
                        onEdit: () => onEdit(t),
                        onDelete: () => onDelete(t.id),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  SliverToBoxAdapter _sectionHeader(String title, ErrTheme t) =>
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Text(
            title,
            style: TextStyle(
              color: t.statLabel,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
        ),
      );
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.theme,
    required this.isActive,
    required this.onTap,
    this.onEdit,
    this.onDelete,
  });

  final ErrTheme theme;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final t = theme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: t.screenBackground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive ? t.startActive : t.toggleBorder,
            width: isActive ? 2.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(30),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Mini app bar
            Container(
              height: 18,
              decoration: BoxDecoration(
                color: t.appBarBackground,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(9)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    Container(
                      width: 30, height: 5,
                      decoration: BoxDecoration(
                        color: t.appBarTitle.withAlpha(200),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const Spacer(),
                    if (isActive)
                      Icon(Icons.check, size: 10, color: t.startActive),
                  ],
                ),
              ),
            ),
            // Body
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 5, 6, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 7, width: 44,
                      decoration: BoxDecoration(
                        color: t.statValue.withAlpha(220),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      height: 5, width: 30,
                      decoration: BoxDecoration(
                        color: t.statLabel.withAlpha(160),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        _pill(t.startActive),
                        const SizedBox(width: 4),
                        _pill(t.stopActive),
                        if (onEdit != null || onDelete != null) ...[
                          const Spacer(),
                          if (onEdit != null)
                            GestureDetector(
                              onTap: onEdit,
                              child: Icon(Icons.edit,
                                  size: 12, color: t.statLabel),
                            ),
                          if (onDelete != null) ...[
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: onDelete,
                              child: Icon(Icons.delete,
                                  size: 12, color: t.stopActive),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Name
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 2, 6, 5),
              child: Text(
                t.name,
                style: TextStyle(
                  color: t.statLabel,
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(Color color) => Container(
        height: 9,
        width: 18,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(5),
        ),
      );
}

class _NewThemeCard extends StatelessWidget {
  const _NewThemeCard({required this.activeTheme, required this.onTap});

  final ErrTheme activeTheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: activeTheme.screenBackground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: activeTheme.toggleBorder,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_outline,
                color: activeTheme.startActive, size: 28),
            const SizedBox(height: 6),
            Text(
              'New Theme',
              style: TextStyle(
                color: activeTheme.statLabel,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
