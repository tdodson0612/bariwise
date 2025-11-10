import 'package:flutter/material.dart';

String getFaceEmoji(int score) {
  if (score <= 25) return '😠';
  if (score <= 49) return '☹️';
  if (score <= 74) return '😐';
  return '😄';
}

class LiverHealthBar extends StatelessWidget {
  final int healthScore;

  const LiverHealthBar({super.key, required this.healthScore});

  @override
  Widget build(BuildContext context) {
    final face = getFaceEmoji(healthScore);

    return Column(
      children: [
        // Score text above the bar
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'Liver Health Score: $healthScore/100',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        
        const SizedBox(height: 40),
        
        // Stack with proper sizing for emoji
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          height: 60, // Give enough height for emoji above bar
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Gradient Bar
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 25,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(
                      colors: [Colors.red, Colors.orange, Colors.yellow, Colors.green],
                    ),
                  ),
                ),
              ),
              // Emoji sliding over bar
              Positioned(
                left: (MediaQuery.of(context).size.width - 64) * (healthScore / 100) - 14,
                top: 0,
                child: Text(
                  face,
                  style: const TextStyle(fontSize: 28),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}