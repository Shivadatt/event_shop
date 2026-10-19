import 'package:flutter/material.dart';
import 'package:om_events/app/core/widgets/om_media_image.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/media_ref.dart';

/// Product image rail: a hero image plus a horizontal thumbnail strip. Falls back to a single
/// labelled "no image" tile when the product has no photos — the buyer must be able to tell
/// "no image exists" apart from "image failed to load".
final class ProductGallery extends StatefulWidget {
  const ProductGallery({super.key, required this.images, required this.productName});

  final List<MediaRef> images;
  final String productName;

  @override
  State<ProductGallery> createState() => _ProductGalleryState();
}

class _ProductGalleryState extends State<ProductGallery> {
  int _selected = 0;

  @override
  void didUpdateWidget(covariant ProductGallery old) {
    super.didUpdateWidget(old);
    if (old.images != widget.images || _selected >= widget.images.length) {
      _selected = widget.images.isEmpty ? 0 : _selected.clamp(0, widget.images.length - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.images;
    final hasImages = images.isNotEmpty;
    final active = hasImages
        ? images[_selected.clamp(0, images.length - 1)]
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AspectRatio(
          aspectRatio: 1,
          child: hasImages
              ? OmMediaImage(ref: active, useThumbnail: false)
              : const OmMediaImage(ref: null),
        ),
        if (hasImages && images.length > 1) ...<Widget>[
          const SizedBox(height: OmSpacing.sm),
          SizedBox(
            height: 76,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
              separatorBuilder: (_, _) => const SizedBox(width: OmSpacing.sm),
              itemBuilder: (context, index) {
                final selected = index == _selected;
                return Semantics(
                  button: true,
                  selected: selected,
                  label: 'Show image ${index + 1} of ${widget.productName}',
                  child: GestureDetector(
                    onTap: () => setState(() => _selected = index),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 68,
                      height: 68,
                      decoration: BoxDecoration(
                        borderRadius: OmRadius.smAll,
                        border: Border.all(
                          color: selected ? OmColors.gold : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: OmRadius.smAll,
                        child: OmMediaImage(ref: images[index]),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: OmSpacing.xs),
          OmText(
            'Image ${_selected + 1} of ${images.length}',
            variant: OmTextVariant.caption,
          ),
        ],
      ],
    );
  }
}
