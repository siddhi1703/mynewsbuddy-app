import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({this.configurationMessage, this.onContinueDemo, super.key});

  final String? configurationMessage;
  final VoidCallback? onContinueDemo;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _signUp = false;
  bool _busy = false;
  bool _hidePassword = true;
  String? _error;
  String? _notice;

  bool get _configured => widget.configurationMessage == null;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_configured || !(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    try {
      final auth = Supabase.instance.client.auth;
      if (_signUp) {
        final response = await auth.signUp(
          email: _email.text.trim().toLowerCase(),
          password: _password.text,
          data: {'full_name': _name.text.trim(), 'phone': _phone.text.trim()},
        );
        if (response.session == null && mounted) {
          setState(() {
            _notice = 'Check your email to confirm the new account.';
          });
        }
      } else {
        await auth.signInWithPassword(
          email: _email.text.trim().toLowerCase(),
          password: _password.text,
        );
      }
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not connect. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFA9D7FF), Color(0xFFE7DEFF), Color(0xFFFFDCE7)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  children: [
                    Text(
                      'Local Companion',
                      textAlign: TextAlign.center,
                      style: Theme.of(
                        context,
                      ).textTheme.headlineLarge?.copyWith(fontSize: 44),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Trusted answers for your community',
                      style: TextStyle(
                        color: Color(0xFF42558F),
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 30),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.40),
                        borderRadius: BorderRadius.circular(34),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            SegmentedButton<bool>(
                              segments: const [
                                ButtonSegment(
                                  value: false,
                                  label: Text('Sign In'),
                                ),
                                ButtonSegment(
                                  value: true,
                                  label: Text('Sign Up'),
                                ),
                              ],
                              selected: {_signUp},
                              showSelectedIcon: false,
                              onSelectionChanged: (selection) {
                                setState(() {
                                  _signUp = selection.first;
                                  _error = null;
                                  _notice = null;
                                });
                              },
                            ),
                            const SizedBox(height: 18),
                            if (_signUp) ...[
                              TextFormField(
                                controller: _name,
                                decoration: const InputDecoration(
                                  prefixIcon: Icon(Icons.person_rounded),
                                  labelText: 'Name',
                                ),
                                validator: (value) =>
                                    (value?.trim().length ?? 0) < 2
                                    ? 'Enter your name.'
                                    : null,
                              ),
                              const SizedBox(height: 12),
                            ],
                            TextFormField(
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.email],
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.email_rounded),
                                labelText: 'Email',
                              ),
                              validator: (value) {
                                final email = value?.trim() ?? '';
                                return email.contains('@') &&
                                        email.contains('.')
                                    ? null
                                    : 'Enter a valid email.';
                              },
                            ),
                            if (_signUp) ...[
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _phone,
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(
                                  prefixIcon: Icon(Icons.phone_rounded),
                                  labelText: 'Phone with country code',
                                  hintText: '+16175550123',
                                ),
                                validator: (value) {
                                  final phone = value?.trim() ?? '';
                                  return RegExp(
                                        r'^\+[0-9]{8,15}$',
                                      ).hasMatch(phone)
                                      ? null
                                      : 'Use a country code, for example +1.';
                                },
                              ),
                            ],
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _password,
                              obscureText: _hidePassword,
                              autofillHints: [
                                _signUp
                                    ? AutofillHints.newPassword
                                    : AutofillHints.password,
                              ],
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.lock_rounded),
                                labelText: 'Password',
                                suffixIcon: IconButton(
                                  onPressed: () => setState(
                                    () => _hidePassword = !_hidePassword,
                                  ),
                                  icon: Icon(
                                    _hidePassword
                                        ? Icons.visibility_rounded
                                        : Icons.visibility_off_rounded,
                                  ),
                                ),
                              ),
                              validator: (value) => (value?.length ?? 0) < 8
                                  ? 'Use at least 8 characters.'
                                  : null,
                              onFieldSubmitted: (_) => _submit(),
                            ),
                            if (widget.configurationMessage != null) ...[
                              const SizedBox(height: 14),
                              _StatusBanner(
                                text: widget.configurationMessage!,
                                icon: Icons.info_rounded,
                                color: const Color(0xFF5D36E8),
                              ),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 14),
                              _StatusBanner(
                                text: _error!,
                                icon: Icons.error_rounded,
                                color: Colors.red,
                              ),
                            ],
                            if (_notice != null) ...[
                              const SizedBox(height: 14),
                              _StatusBanner(
                                text: _notice!,
                                icon: Icons.mark_email_read_rounded,
                                color: Colors.green,
                              ),
                            ],
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: _busy || !_configured
                                    ? null
                                    : _submit,
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 17,
                                  ),
                                  backgroundColor: const Color(0xFF5D36E8),
                                ),
                                child: _busy
                                    ? const SizedBox.square(
                                        dimension: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(_signUp ? 'Sign Up' : 'Sign In'),
                              ),
                            ),
                            if (widget.onContinueDemo != null) ...[
                              const SizedBox(height: 8),
                              TextButton.icon(
                                onPressed: widget.onContinueDemo,
                                icon: const Icon(
                                  Icons.play_circle_outline_rounded,
                                ),
                                label: const Text(
                                  'Continue in backup demo mode',
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.text,
    required this.icon,
    required this.color,
  });

  final String text;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: color)),
          ),
        ],
      ),
    );
  }
}
