// lib/widgets/surgery_type_selector.dart

import 'package:flutter/material.dart';
import '../models/surgery_nutrition_profile.dart';

class SurgeryTypeSelector extends StatelessWidget {
  final String currentValue;
  final Function(String) onChanged;
  final bool showGuidance;

  const SurgeryTypeSelector({
    super.key,
    required this.currentValue,
    required this.onChanged,
    this.showGuidance = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Dropdown selector
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: DropdownButtonFormField<String>(
            value: currentValue.isEmpty 
                ? SurgeryNutritionProfile.OTHER 
                : currentValue,
            decoration: const InputDecoration(
              labelText: 'Which type of bari surgery do you have?',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            isExpanded: true,
            items: SurgeryNutritionProfile.getAllSurgeryTypes()
                .map((type) => DropdownMenuItem(
                      value: type,
                      child: Text(
                        type,
                        style: const TextStyle(fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ))
                .toList(),
            onChanged: (value) {
              if (value != null) {
                onChanged(value);
              }
            },
          ),
        ),

        // Guidance text
        if (showGuidance && currentValue.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  color: Colors.blue.shade700,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    SurgeryNutritionProfile.getSurgeryGuidance(currentValue),
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.blue.shade900,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // Educational disclaimer
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.medical_information_outlined,
                color: Colors.orange.shade700,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'This scoring is for educational purposes only. Always consult your physician for medical advice.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange.shade900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}