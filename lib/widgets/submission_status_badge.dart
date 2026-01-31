// lib/widgets/submission_status_badge.dart
// Colored status badge for recipe submissions
// iOS 14 Compatible | Production Ready

import 'package:flutter/material.dart';
import '../models/recipe_submission.dart';

class SubmissionStatusBadge extends StatelessWidget {
  final SubmissionStatus status;
  final bool showIcon;
  final bool compact;

  const SubmissionStatusBadge({
    super.key,
    required this.status,
    this.showIcon = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _getBackgroundColor(),
        borderRadius: BorderRadius.circular(compact ? 4 : 6),
        border: Border.all(
          color: _getBorderColor(),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon) ...[
            Text(
              _getIcon(),
              style: TextStyle(
                fontSize: compact ? 12 : 14,
              ),
            ),
            SizedBox(width: compact ? 4 : 6),
          ],
          Text(
            _getText(),
            style: TextStyle(
              color: _getTextColor(),
              fontSize: compact ? 11 : 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Color _getBackgroundColor() {
    switch (status) {
      case SubmissionStatus.pending:
        return Colors.orange.shade50;
      case SubmissionStatus.approved:
        return Colors.orange.shade50;
      case SubmissionStatus.rejected:
        return Colors.red.shade50;
    }
  }

  Color _getBorderColor() {
    switch (status) {
      case SubmissionStatus.pending:
        return Colors.orange.shade300;
      case SubmissionStatus.approved:
        return Colors.orange.shade300;
      case SubmissionStatus.rejected:
        return Colors.red.shade300;
    }
  }

  Color _getTextColor() {
    switch (status) {
      case SubmissionStatus.pending:
        return Colors.orange.shade800;
      case SubmissionStatus.approved:
        return Colors.orange.shade800;
      case SubmissionStatus.rejected:
        return Colors.red.shade800;
    }
  }

  String _getIcon() {
    switch (status) {
      case SubmissionStatus.pending:
        return '⏳';
      case SubmissionStatus.approved:
        return '✓';
      case SubmissionStatus.rejected:
        return '✗';
    }
  }

  String _getText() {
    switch (status) {
      case SubmissionStatus.pending:
        return 'Pending Review';
      case SubmissionStatus.approved:
        return 'Approved';
      case SubmissionStatus.rejected:
        return 'Rejected';
    }
  }
}