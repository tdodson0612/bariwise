// lib/widgets/add_to_cookbook_button.dart
import 'package:flutter/material.dart';
import '../services/cookbook_service.dart';
import '../config/app_config.dart';

class AddToCookbookButton extends StatefulWidget {
  final String recipeName;
  final String ingredients;
  final String directions;
  final int? recipeId;
  final bool compact;
  final VoidCallback? onSuccess;

  const AddToCookbookButton({
    super.key,
    required this.recipeName,
    required this.ingredients,
    required this.directions,
    this.recipeId,
    this.compact = false,
    this.onSuccess,
  });

  @override
  State<AddToCookbookButton> createState() => _AddToCookbookButtonState();
}

class _AddToCookbookButtonState extends State<AddToCookbookButton> {
  bool _isAdding = false;
  bool _isAdded = false;
  bool _isInCookbook = false;

  @override
  void initState() {
    super.initState();
    _checkIfInCookbook();
  }

  Future<void> _checkIfInCookbook() async {
    try {
      final inCookbook = await CookbookService.isInCookbook(
        recipeId: widget.recipeId,
        recipeName: widget.recipeName,
      );
      if (mounted) {
        setState(() => _isInCookbook = inCookbook);
      }
    } catch (e) {
      AppConfig.debugPrint('Error checking cookbook: $e');
    }
  }

  Future<void> _handleAddToCookbook() async {
    if (_isAdding || _isAdded || _isInCookbook) return;

    setState(() => _isAdding = true);

    try {
      await CookbookService.addToCookbook(
        widget.recipeName,
        widget.ingredients,
        widget.directions,
        recipeId: widget.recipeId,
      );

      if (mounted) {
        setState(() {
          _isAdded = true;
          _isInCookbook = true;
        });

        widget.onSuccess?.call();

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Added to cookbook!'),
                ),
              ],
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );

        // Reset _isAdded after animation
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            setState(() => _isAdded = false);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isAdding = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isInCookbook && !_isAdded) {
      // Already in cookbook - show disabled state
      return widget.compact
          ? _buildCompactButton(
              icon: Icons.bookmark,
              color: Colors.grey,
              onPressed: null,
            )
          : _buildFullButton(
              icon: Icons.bookmark,
              label: 'In Cookbook',
              color: Colors.grey,
              onPressed: null,
            );
    }

    if (_isAdded) {
      // Just added - show success state
      return widget.compact
          ? _buildCompactButton(
              icon: Icons.check,
              color: Colors.orange,
              onPressed: null,
            )
          : _buildFullButton(
              icon: Icons.check,
              label: 'Added!',
              color: Colors.orange,
              onPressed: null,
            );
    }

    // Ready to add
    return widget.compact
        ? _buildCompactButton(
            icon: _isAdding ? null : Icons.bookmark_add,
            color: Colors.orange,
            onPressed: _handleAddToCookbook,
          )
        : _buildFullButton(
            icon: _isAdding ? null : Icons.bookmark_add,
            label: _isAdding ? 'Adding...' : 'Add to Cookbook',
            color: Colors.orange,
            onPressed: _handleAddToCookbook,
          );
  }

  Widget _buildCompactButton({
    IconData? icon,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return IconButton(
      onPressed: onPressed,
      icon: _isAdding
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : Icon(icon, color: Colors.white),
      style: IconButton.styleFrom(
        backgroundColor: color,
        disabledBackgroundColor: color.withOpacity(0.6),
        padding: const EdgeInsets.all(8),
      ),
      tooltip: onPressed == null ? 'In Cookbook' : 'Add to Cookbook',
    );
  }

  Widget _buildFullButton({
    IconData? icon,
    required String label,
    required Color color,
    required VoidCallback? onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: _isAdding
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : Icon(icon, color: Colors.white),
      label: Text(
        label,
        style: const TextStyle(color: Colors.white),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        disabledBackgroundColor: color.withOpacity(0.6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}