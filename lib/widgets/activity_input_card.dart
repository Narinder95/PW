import 'package:flutter/material.dart';

class ActivityInputCard extends StatefulWidget {
  final String icon;
  final String label;
  final String unit;
  final int value;
  final Function(int) onChanged;
  final List<int> presets;
  final Color color;

  const ActivityInputCard({
    Key? key,
    required this.icon,
    required this.label,
    required this.unit,
    required this.value,
    required this.onChanged,
    required this.presets,
    required this.color,
  }) : super(key: key);

  @override
  State<ActivityInputCard> createState() => _ActivityInputCardState();
}

class _ActivityInputCardState extends State<ActivityInputCard> {
  int _sliderValue = 0;

  String _formatSliderLabel(int val) {
    if (widget.unit == 'L') {
      if (val == 0) return '0 ml';
      if (val < 1000) return '$val ml';
      final liters = val / 1000;
      return '${liters.toStringAsFixed(1)} L';
    }
    return '+$val ${widget.unit}';
  }

  int _getUnitIncrement() {
    switch (widget.unit) {
      case 'L':
        return 100; // ml
      case 'k':
        return 500; // steps
      case 'min':
      case 'h':
      default:
        return 1;
    }
  }

  int _getGoalRaw() {
    switch (widget.label) {
      case 'Water':
        return 2000; // ml
      case 'Exercise':
        return 30;
      case 'Sleep':
        return 8;
      case 'Meditate':
        return 15;
      case 'Read':
        return 20;
      case 'Steps':
        return 10000;
      default:
        return 100;
    }
  }

  String _getGoalLabel() {
    switch (widget.label) {
      case 'Water':
        return '2 L';
      case 'Exercise':
        return '30 min';
      case 'Sleep':
        return '8 h';
      case 'Meditate':
        return '15 min';
      case 'Read':
        return '20 min';
      case 'Steps':
        return '10k';
      default:
        return '';
    }
  }

  double _getProgressPercentage() {
    final goal = _getGoalRaw();
    if (goal == 0) return 0;
    return (widget.value / goal).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final unitIncrement = _getUnitIncrement();
    final maxSliderVal = unitIncrement * 20;
    final sliderFillPercent =
        maxSliderVal == 0 ? 0.0 : (_sliderValue / maxSliderVal * 100).clamp(0.0, 100.0);

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final bgGradientColor = isDarkMode ? const Color(0xFF1E293B) : const Color(0xFFF5F5F7);
    final borderColor = isDarkMode ? Colors.white.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.2);
    final labelColor = isDarkMode ? Colors.grey : Colors.grey[600];

    return Container(
      width: 168,
      height: 204,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            bgGradientColor.withValues(alpha: 0.4),
            bgGradientColor.withValues(alpha: 0.2),
          ],
        ),
        border: Border.all(
          color: borderColor,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left vertical slider — its own reserved column, not part of the
          // content box, so the content can be centered symmetrically.
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 12, bottom: 12),
            child: SizedBox(
              width: 20,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final trackHeight = constraints.maxHeight;
                  void updateFromLocalY(double y) {
                    final clampedY = y.clamp(0.0, trackHeight);
                    final percentageFromBottom =
                        ((trackHeight - clampedY) / trackHeight * 100)
                            .clamp(0.0, 100.0);
                    final newSliderValue =
                        ((percentageFromBottom / 100) * maxSliderVal / unitIncrement)
                                .round() *
                            unitIncrement;

                    if (newSliderValue != _sliderValue) {
                      setState(() {
                        _sliderValue = newSliderValue;
                      });
                    }
                  }

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    // A single tap jumps the thumb straight to that point, in
                    // addition to the drag below — without this a tap on the
                    // track did nothing because it never fired a drag event.
                    onTapDown: (details) =>
                        updateFromLocalY(details.localPosition.dy),
                    onVerticalDragStart: (details) =>
                        updateFromLocalY(details.localPosition.dy),
                    onVerticalDragUpdate: (details) =>
                        updateFromLocalY(details.localPosition.dy),
                    child: CustomPaint(
                      size: Size(20, trackHeight),
                      painter: _SliderPainter(
                        fillPercentage: sliderFillPercent,
                        color: widget.color,
                        isDarkMode: isDarkMode,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          // Content — symmetric padding on both sides so it's truly centered
          // within its own box.
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Emoji
                  Transform.translate(
                    offset: const Offset(-6, 0),
                    child: Text(
                      widget.icon,
                      style: const TextStyle(fontSize: 28, height: 1.0),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  // Label
                  Transform.translate(
                    offset: const Offset(-6, 0),
                    child: Text(
                      widget.label.toUpperCase(),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: labelColor,
                        height: 1.0,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  // Value + goal (inline, same line) + progress bar
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            widget.value.toString(),
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              color: widget.color,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '/ ${_getGoalLabel()}',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: labelColor,
                              height: 1.0,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: SizedBox(
                          height: 4,
                          child: LinearProgressIndicator(
                            value: _getProgressPercentage(),
                            backgroundColor: isDarkMode
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.grey.withValues(alpha: 0.2),
                            valueColor: AlwaysStoppedAnimation(widget.color),
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Reserved slot for preview label (fixed height so layout never jumps)
                  SizedBox(
                    height: 12,
                    child: Center(
                      child: _sliderValue > 0
                          ? Text(
                              _formatSliderLabel(_sliderValue),
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: widget.color,
                                height: 1.0,
                              ),
                            )
                          : null,
                    ),
                  ),
                  // Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildControlButton(
                        '−',
                        () {
                          if (widget.value > 0) {
                            widget.onChanged(
                              (widget.value - unitIncrement).clamp(0, 1 << 30),
                            );
                          }
                        },
                      ),
                      const SizedBox(width: 6),
                      _buildControlButton(
                        '+',
                        () {
                          final amountToAdd =
                              _sliderValue > 0 ? _sliderValue : unitIncrement;
                          widget.onChanged(widget.value + amountToAdd);
                          setState(() {
                            _sliderValue = 0;
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton(String label, VoidCallback onPressed) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final btnBgColor = isDarkMode
      ? Colors.white.withValues(alpha: 0.05)
      : Colors.grey.withValues(alpha: 0.1);
    final btnBorderColor = isDarkMode
      ? Colors.white.withValues(alpha: 0.12)
      : Colors.grey.withValues(alpha: 0.3);

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: btnBgColor,
          border: Border.all(
            color: btnBorderColor,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: widget.color,
              height: 1.0,
            ),
          ),
        ),
      ),
    );
  }
}

class _SliderPainter extends CustomPainter {
  final double fillPercentage;
  final Color color;
  final bool isDarkMode;

  _SliderPainter({
    required this.fillPercentage,
    required this.color,
    required this.isDarkMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const trackWidth = 4.0;
    final trackLeft = (size.width - trackWidth) / 2;

    // Track background - theme-aware
    final trackColor = isDarkMode
      ? Colors.white.withValues(alpha: 0.08)
      : Colors.grey.withValues(alpha: 0.3);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(trackLeft, 0, trackWidth, size.height),
        const Radius.circular(2),
      ),
      Paint()..color = trackColor,
    );

    // Fill from bottom
    final fillHeight = size.height * (fillPercentage / 100);
    if (fillHeight > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            trackLeft,
            size.height - fillHeight,
            trackWidth,
            fillHeight,
          ),
          const Radius.circular(2),
        ),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.5),
              color,
            ],
          ).createShader(
            Rect.fromLTWH(
              trackLeft,
              size.height - fillHeight,
              trackWidth,
              fillHeight,
            ),
          ),
      );
    }

    // Thumb — always visible, sits at the current fill position (bottom = 0)
    final thumbY = size.height - fillHeight;
    canvas.drawCircle(
      Offset(size.width / 2, thumbY),
      9,
      Paint()
        ..color = color.withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(
      Offset(size.width / 2, thumbY),
      7,
      Paint()..color = color,
    );
    canvas.drawCircle(
      Offset(size.width / 2, thumbY),
      7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.3),
    );
  }

  @override
  bool shouldRepaint(covariant _SliderPainter oldDelegate) =>
      oldDelegate.fillPercentage != fillPercentage ||
      oldDelegate.color != color ||
      oldDelegate.isDarkMode != isDarkMode;
}
