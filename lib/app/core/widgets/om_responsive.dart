import 'package:flutter/material.dart';
import 'package:om_events/app/theme/om_tokens.dart';

/// Caps content width so a 27-inch monitor shows a centred column instead of fifteen stretched
/// cards. Wrap page bodies, not full-bleed heroes.
final class OmContentWidth extends StatelessWidget {
  const OmContentWidth({
    super.key,
    required this.child,
    this.maxWidth = OmSpacing.pageMaxWidth,
    this.padding = const EdgeInsets.symmetric(horizontal: OmSpacing.md),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Padding(padding: padding, child: child),
        ),
      );
}

/// Picks a layout per device class.
final class OmCompactSwitch extends StatelessWidget {
  const OmCompactSwitch({super.key, required this.compact, required this.wide});

  final Widget compact;
  final Widget wide;

  @override
  Widget build(BuildContext context) => context.isCompactLayout ? compact : wide;
}

final class OmBreakpointBuilder extends StatelessWidget {
  const OmBreakpointBuilder({
    super.key,
    required this.mobile,
    required this.tablet,
    required this.laptop,
    required this.desktop,
  });

  final Widget mobile;
  final Widget tablet;
  final Widget laptop;
  final Widget desktop;

  @override
  Widget build(BuildContext context) => switch (context.deviceClass) {
        OmDeviceClass.mobile => mobile,
        OmDeviceClass.tablet => tablet,
        OmDeviceClass.laptop => laptop,
        OmDeviceClass.desktop => desktop,
      };
}

/// Product grid sized by the breakpoint token, so a new screen size is a one-line change rather
/// than a hunt through every list.
///
/// [shrinkWrap] is for grids nested in a page `SingleChildScrollView`; those grids must not scroll
/// independently, or the mouse wheel traps the viewport on desktop.
final class OmProductGrid extends StatelessWidget {
  const OmProductGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.columns,
    this.aspectRatio,
    this.spacing = OmSpacing.md,
    this.shrinkWrap = true,
  });

  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final int? columns;
  final double? aspectRatio;
  final double spacing;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) => GridView.builder(
        shrinkWrap: shrinkWrap,
        physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
        padding: EdgeInsets.zero,
        itemCount: itemCount,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns ?? context.omColumnCount,
          crossAxisSpacing: spacing,
          mainAxisSpacing: spacing,
          childAspectRatio: aspectRatio ?? context.omGridAspectRatio,
        ),
        itemBuilder: itemBuilder,
      );
}

/// The same grid as a sliver, for pages that scroll a header into the shelf.
final class OmProductGridSliver extends StatelessWidget {
  const OmProductGridSliver({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.columns,
    this.aspectRatio,
    this.spacing = OmSpacing.md,
  });

  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final int? columns;
  final double? aspectRatio;
  final double spacing;

  @override
  Widget build(BuildContext context) => SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns ?? context.omColumnCount,
          crossAxisSpacing: spacing,
          mainAxisSpacing: spacing,
          childAspectRatio: aspectRatio ?? context.omGridAspectRatio,
        ),
        delegate: SliverChildBuilderDelegate(itemBuilder, childCount: itemCount),
      );
}

/// Never let a table force the page sideways. On phones the caller supplies a card list and this
/// returns it; on wide screens it returns the table.
final class OmResponsiveTable extends StatelessWidget {
  const OmResponsiveTable({
    super.key,
    required this.table,
    required this.asCards,
    this.minTableWidth = 900,
  });

  final Widget table;
  final Widget asCards;
  final double minTableWidth;

  @override
  Widget build(BuildContext context) =>
      context.screenWidth >= minTableWidth ? table : asCards;
}

/// Horizontal scroll only where it is intentional (image carousels, chip rows). Data tables use
/// [OmResponsiveTable] instead of scrolling sideways off the page.
final class OmHorizontalScroller extends StatelessWidget {
  const OmHorizontalScroller({
    super.key,
    required this.children,
    this.height = 120,
    this.spacing = OmSpacing.sm,
  });

  final List<Widget> children;
  final double height;
  final double spacing;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: children.length,
          separatorBuilder: (_, _) => SizedBox(width: spacing),
          itemBuilder: (context, index) => children[index],
        ),
      );
}
