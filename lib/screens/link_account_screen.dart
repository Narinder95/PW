import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api/api_exception.dart';
import '../utils/journal_theme.dart';
import '../widgets/app_scope.dart';

/// Claims an auto-provisioned account by attaching an email or phone number.
///
/// There is no sign-up screen in this app: an account is created silently on
/// first launch, which means it lives only on this device. This screen is how
/// the user makes it recoverable — and it is the only place credentials are
/// ever asked for.
class LinkAccountScreen extends StatefulWidget {
  const LinkAccountScreen({super.key});

  @override
  State<LinkAccountScreen> createState() => _LinkAccountScreenState();
}

enum _Method { email, phone }

class _LinkAccountScreenState extends State<LinkAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _contact = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _username = TextEditingController();

  _Method _method = _Method.email;
  bool _submitting = false;
  bool _obscure = true;
  String? _serverError;

  /// Server-reported field errors, so a 400 lands on the right input.
  final Map<String, String> _fieldErrors = <String, String>{};

  bool _seededHandle = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Seed the handle with the auto-generated one so the user can keep it.
    // Not in initState: inherited widgets are not available that early.
    if (_seededHandle) return;
    _seededHandle = true;
    final profile = AppScope.read(context).auth.user;
    if (profile != null) _username.text = profile.username;
  }

  @override
  void dispose() {
    _contact.dispose();
    _password.dispose();
    _confirm.dispose();
    _username.dispose();
    super.dispose();
  }

  String? _validateContact(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) {
      return _method == _Method.email
          ? 'Enter your email address'
          : 'Enter your phone number';
    }
    if (_method == _Method.email) {
      if (!value.contains('@') || value.length < 3) return 'That does not look like an email';
    } else {
      final cleaned = value.replaceAll(RegExp(r'[\s()\-.]'), '');
      if (!RegExp(r'^\+?[0-9]{7,15}$').hasMatch(cleaned)) {
        return 'Enter 7-15 digits, optionally starting with +';
      }
    }
    return _fieldErrors[_method == _Method.email ? 'email' : 'phone'];
  }

  String? _validatePassword(String? raw) {
    final value = raw ?? '';
    if (value.length < 8) return 'At least 8 characters';
    return _fieldErrors['password'];
  }

  String? _validateUsername(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    if (value.isEmpty) return 'Pick a handle';
    if (value.length < 3 || value.length > 20) return '3-20 characters';
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(value)) {
      return 'Only a-z, 0-9 and _';
    }
    return _fieldErrors['username'];
  }

  Future<void> _submit() async {
    setState(() {
      _serverError = null;
      _fieldErrors.clear();
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_password.text != _confirm.text) {
      setState(() => _serverError = 'The two passwords do not match');
      return;
    }

    setState(() => _submitting = true);
    final auth = AppScope.read(context).auth;
    final contact = _contact.text.trim();

    try {
      await auth.linkAccount(
        email: _method == _Method.email ? contact : null,
        phone: _method == _Method.phone ? contact : null,
        password: _password.text,
        username: _username.text.trim().toLowerCase(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        if (error.field != null) {
          _fieldErrors[error.field!] = error.message;
          _formKey.currentState?.validate();
        } else {
          _serverError = error.isNetwork
              ? "Couldn't reach the server. Check your connection and try again."
              : error.message;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = JournalTheme.of(context);

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text('Save your account'),
        backgroundColor: t.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: t.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _explainer(t),
                const SizedBox(height: 24),
                _methodToggle(t),
                const SizedBox(height: 16),
                _field(
                  t: t,
                  controller: _contact,
                  label: _method == _Method.email ? 'Email address' : 'Phone number',
                  hint: _method == _Method.email ? 'you@example.com' : '+91 98765 43210',
                  keyboardType: _method == _Method.email
                      ? TextInputType.emailAddress
                      : TextInputType.phone,
                  validator: _validateContact,
                  autofillHints: _method == _Method.email
                      ? const [AutofillHints.email]
                      : const [AutofillHints.telephoneNumber],
                ),
                const SizedBox(height: 14),
                _field(
                  t: t,
                  controller: _username,
                  label: 'Handle',
                  hint: 'how friends find you',
                  validator: _validateUsername,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')),
                    LengthLimitingTextInputFormatter(20),
                  ],
                ),
                const SizedBox(height: 14),
                _field(
                  t: t,
                  controller: _password,
                  label: 'Password',
                  hint: 'at least 8 characters',
                  obscure: _obscure,
                  validator: _validatePassword,
                  autofillHints: const [AutofillHints.newPassword],
                  suffix: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      color: t.textMuted,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                const SizedBox(height: 14),
                _field(
                  t: t,
                  controller: _confirm,
                  label: 'Confirm password',
                  hint: 'type it again',
                  obscure: _obscure,
                  validator: (v) =>
                      (v ?? '').isEmpty ? 'Type your password again' : null,
                ),
                if (_serverError != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: t.incomplete.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(JournalTheme.radiusTile),
                      border: Border.all(color: t.incomplete.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: t.incomplete, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _serverError!,
                            style: TextStyle(color: t.textPrimary, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: t.action,
                    foregroundColor: t.onAccent(t.action),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(JournalTheme.radiusTile),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save account'),
                ),
                const SizedBox(height: 12),
                Text(
                  'Your habits, streaks and friends stay exactly as they are.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: t.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _explainer(JournalTheme t) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surfaceBright,
        borderRadius: BorderRadius.circular(JournalTheme.radiusCard),
        border: Border.all(color: t.outline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.phonelink_lock_outlined, color: t.action, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Right now this account only exists on this phone. Add an email '
              'or phone number and it can be restored if you reinstall the app '
              'or switch devices.',
              style: TextStyle(fontSize: 13, height: 1.5, color: t.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _methodToggle(JournalTheme t) {
    return SegmentedButton<_Method>(
      segments: const [
        ButtonSegment(
          value: _Method.email,
          label: Text('Email'),
          icon: Icon(Icons.alternate_email, size: 18),
        ),
        ButtonSegment(
          value: _Method.phone,
          label: Text('Phone'),
          icon: Icon(Icons.phone_outlined, size: 18),
        ),
      ],
      selected: {_method},
      onSelectionChanged: (selection) {
        setState(() {
          _method = selection.first;
          _contact.clear();
          _fieldErrors.remove('email');
          _fieldErrors.remove('phone');
        });
      },
      style: SegmentedButton.styleFrom(
        backgroundColor: t.surface,
        foregroundColor: t.textSecondary,
        selectedBackgroundColor: t.action.withValues(alpha: 0.18),
        selectedForegroundColor: t.action,
        side: BorderSide(color: t.outline),
      ),
    );
  }

  Widget _field({
    required JournalTheme t,
    required TextEditingController controller,
    required String label,
    required String hint,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    bool obscure = false,
    Widget? suffix,
    List<String>? autofillHints,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      obscureText: obscure,
      autofillHints: autofillHints,
      inputFormatters: inputFormatters,
      autocorrect: false,
      style: TextStyle(color: t.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: t.surface,
        suffixIcon: suffix,
        labelStyle: TextStyle(color: t.textSecondary),
        hintStyle: TextStyle(color: t.textMuted.withValues(alpha: 0.7)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(JournalTheme.radiusTile),
          borderSide: BorderSide(color: t.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(JournalTheme.radiusTile),
          borderSide: BorderSide(color: t.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(JournalTheme.radiusTile),
          borderSide: BorderSide(color: t.action, width: 2),
        ),
      ),
    );
  }
}
