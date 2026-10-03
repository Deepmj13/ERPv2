import 'package:flutter/material.dart';

/// Persistent inline feedback for the login/register forms.
///
/// Renders nothing when there is no message, so callers can drop it in
/// unconditionally. When [isServerUnreachable] is set it also offers a retry
/// affordance and shows the configured API base URL, which is the first thing
/// to check when the request never left the device.
class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({
    super.key,
    required this.message,
    this.isServerUnreachable = false,
    this.baseUrl,
    this.onRetry,
    this.onDismiss,
  });

  final String? message;
  final bool isServerUnreachable;
  final String? baseUrl;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final text = message;
    if (text == null || text.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('auth-error-banner'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.error.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isServerUnreachable ? Icons.wifi_off : Icons.error_outline,
                size: 20,
                color: scheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text,
                      key: const Key('auth-error-message'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onErrorContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (isServerUnreachable) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Check that the server is running and reachable.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onErrorContainer,
                        ),
                      ),
                      if (baseUrl != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'API: $baseUrl',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: scheme.onErrorContainer,
                                fontFamily: 'monospace',
                              ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              if (onDismiss != null)
                IconButton(
                  tooltip: 'Dismiss',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  color: scheme.onErrorContainer,
                  onPressed: onDismiss,
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          if (isServerUnreachable && onRetry != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const Key('auth-error-retry'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
