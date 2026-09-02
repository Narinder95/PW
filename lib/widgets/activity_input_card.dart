import 'package:flutter/material.dart';

class ActivityInputCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Container(
      width: 145,
      height: 130,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Icon + Label
            Column(
              children: [
                Text(
                  icon,
                  style: const TextStyle(fontSize: 24),
                ),
                const SizedBox(height: 0),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 9,
                      ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),

            // Value Display
            Text(
              value.toString(),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),

            // Unit
            Text(
              unit,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 7,
                    color: Colors.grey[600],
                  ),
            ),

            // Stepper Controls
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildStepperButton(
                  icon: Icons.remove,
                  onPressed: () {
                    if (value > 0) {
                      onChanged(value - 1);
                    }
                  },
                  color: color,
                ),
                const SizedBox(width: 1),
                _buildStepperButton(
                  icon: Icons.add,
                  onPressed: () {
                    onChanged(value + 1);
                  },
                  color: color,
                ),
              ],
            ),

            // Quick Presets
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: presets
                  .map((preset) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 0.5),
                          child: _buildPresetButton(
                            label: '+$preset',
                            onPressed: () {
                              onChanged(value + preset);
                            },
                            color: color,
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepperButton({
    required IconData icon,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          border: Border.all(
            color: color.withValues(alpha: 0.25),
            width: 0.5,
          ),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Icon(
          icon,
          size: 12,
          color: color,
        ),
      ),
    );
  }

  Widget _buildPresetButton({
    required String label,
    required VoidCallback onPressed,
    required Color color,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          border: Border.all(
            color: color.withValues(alpha: 0.3),
            width: 0.5,
          ),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 6,
            fontWeight: FontWeight.w600,
            color: color,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
