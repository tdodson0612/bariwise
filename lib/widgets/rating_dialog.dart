// lib/widgets/rating_dialog.dart - FIXED: Better error messages
import 'package:flutter/material.dart';
import 'package:bari_wise/services/ratings_service.dart';
import '../services/error_handling_service.dart';

class RatingDialog extends StatefulWidget {
  final int recipeId;
  final String recipeName;
  final int? currentRating;

  const RatingDialog({
    super.key,
    required this.recipeId,
    required this.recipeName,
    this.currentRating,
  });

  @override
  State<RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<RatingDialog> {
  int _selectedRating = 0;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _selectedRating = widget.currentRating ?? 0;
  }

  Future<void> _submitRating() async {
    if (_selectedRating == 0) {
      ErrorHandlingService.showSimpleError(
        context,
        'Please select a rating',
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      await RatingsService.rateRecipe(widget.recipeId, _selectedRating);
      
      if (mounted) {
        Navigator.pop(context, _selectedRating);
        ErrorHandlingService.showSuccess(
          context,
          'Rating submitted successfully!',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });

        // Check for specific error messages
        final errorMsg = e.toString();
        String displayMessage;
        
        if (errorMsg.contains('cannot rate your own recipe')) {
          displayMessage = 'You cannot rate your own recipe';
        } else if (errorMsg.contains('Failed to rate recipe')) {
          displayMessage = 'Unable to submit rating. Please try again.';
        } else {
          displayMessage = 'Unable to submit rating';
        }

        // Show error dialog with proper message
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red.shade700),
                const SizedBox(width: 12),
                const Text('Cannot Rate'),
              ],
            ),
            content: Text(displayMessage),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // Close error dialog
                  Navigator.pop(context); // Close rating dialog
                },
                child: const Text('OK'),
              ),
              if (!errorMsg.contains('cannot rate your own recipe'))
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context); // Close error dialog
                    _submitRating(); // Retry
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Try Again'),
                ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.currentRating != null ? 'Update Rating' : 'Rate Recipe',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.recipeName,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final starValue = index + 1;
              return GestureDetector(
                onTap: _isSubmitting
                    ? null
                    : () {
                        setState(() {
                          _selectedRating = starValue;
                        });
                      },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    starValue <= _selectedRating
                        ? Icons.star
                        : Icons.star_border,
                    size: 48,
                    color: starValue <= _selectedRating
                        ? Colors.amber
                        : Colors.grey.shade400,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          if (_selectedRating > 0)
            Text(
              _getRatingText(_selectedRating),
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submitRating,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Text(widget.currentRating != null ? 'Update' : 'Submit'),
        ),
      ],
    );
  }

  String _getRatingText(int rating) {
    switch (rating) {
      case 1:
        return 'Poor';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      case 4:
        return 'Very Good';
      case 5:
        return 'Excellent';
      default:
        return '';
    }
  }
}