import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../theme/app_design_tokens.dart';
import '../services/google_auth_service.dart';
import '../services/profile_name_store.dart';
import '../widgets/google_profile_avatar.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.user, this.navigationDrawer});

  final User user;
  final Widget? navigationDrawer;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isSigningOut = false;
  String? _loadingProfileNameFor;

  void _loadProfileName(User user) {
    if (_loadingProfileNameFor == user.uid) {
      return;
    }
    _loadingProfileNameFor = user.uid;
    ProfileNameStore.instance
        .load(userId: user.uid, googleName: user.displayName ?? '')
        .catchError((Object error, StackTrace stackTrace) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'Profile name loading',
            ),
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Unable to load the saved profile name.'),
              ),
            );
          }
        });
  }

  Future<void> _editName(User user) async {
    try {
      await ProfileNameStore.instance.load(
        userId: user.uid,
        googleName: user.displayName ?? '',
      );
    } on Object catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'Profile name loading',
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to load the saved profile name.'),
          ),
        );
      }
      return;
    }
    if (!mounted) {
      return;
    }
    final currentName = ProfileNameStore.instance.nameFor(
      userId: user.uid,
      googleName: user.displayName ?? '',
    );
    final controller = TextEditingController(text: currentName);
    final formKey = GlobalKey<FormState>();
    var isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Name'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
              validator: (value) => value?.trim().isNotEmpty == true
                  ? null
                  : 'Name cannot be empty.',
              onFieldSubmitted: (_) {
                if (formKey.currentState?.validate() == true && !isSaving) {
                  setDialogState(() => isSaving = true);
                  _saveProfileName(
                    user,
                    controller.text,
                    dialogContext,
                    onFailure: () => setDialogState(() => isSaving = false),
                  );
                }
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () {
                      if (formKey.currentState?.validate() != true) {
                        return;
                      }
                      setDialogState(() => isSaving = true);
                      _saveProfileName(
                        user,
                        controller.text,
                        dialogContext,
                        onFailure: () => setDialogState(() => isSaving = false),
                      );
                    },
              child: isSaving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
  }

  Future<void> _saveProfileName(
    User user,
    String name,
    BuildContext dialogContext, {
    required VoidCallback onFailure,
  }) async {
    try {
      await ProfileNameStore.instance.save(
        userId: user.uid,
        googleName: user.displayName ?? '',
        name: name,
      );
      if (dialogContext.mounted) {
        Navigator.of(dialogContext).pop();
      }
    } on Object catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'Profile name saving',
        ),
      );
      if (dialogContext.mounted) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          const SnackBar(content: Text('Unable to save the profile name.')),
        );
        onFailure();
      }
    }
  }

  Future<void> _signOut() async {
    if (_isSigningOut) {
      return;
    }
    setState(() => _isSigningOut = true);

    try {
      await GoogleAuthService.instance.signOut();
    } on Object catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'Google sign-out',
        ),
      );
      if (!mounted) {
        return;
      }
      if (GoogleAuthService.instance.currentUser != null) {
        setState(() => _isSigningOut = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to sign out. Please try again.'),
          ),
        );
        return;
      }
    }

    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: widget.navigationDrawer,
      appBar: AppBar(
        leadingWidth: widget.navigationDrawer == null ? null : 104,
        title: const Text('Profile'),
        leading: widget.navigationDrawer == null
            ? null
            : SizedBox(
                width: 104,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Builder(
                      builder: (context) => IconButton(
                        key: const ValueKey('global-navigation-button'),
                        tooltip: 'Open navigation menu',
                        onPressed: () => Scaffold.of(context).openDrawer(),
                        icon: const Icon(Icons.menu_rounded),
                      ),
                    ),
                    if (Navigator.of(context).canPop())
                      IconButton(
                        tooltip: 'Back',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                  ],
                ),
              ),
      ),
      body: StreamBuilder<User?>(
        stream: GoogleAuthService.instance.authStateChanges,
        initialData: GoogleAuthService.instance.currentUser ?? widget.user,
        builder: (context, snapshot) {
          final user = snapshot.data;
          if (snapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Text('Profile information is unavailable.'),
              ),
            );
          }
          if (user == null) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Text('No Google account is currently signed in.'),
              ),
            );
          }
          _loadProfileName(user);

          final colorScheme = Theme.of(context).colorScheme;
          final email = user.email?.trim();
          return SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Card(
                    elevation: AppElevation.subtle,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl,
                        vertical: AppSpacing.xxxl,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GoogleProfileAvatar(user: user, radius: 52),
                          const SizedBox(height: AppSpacing.lg),
                          AnimatedBuilder(
                            animation: ProfileNameStore.instance,
                            builder: (context, child) => Text(
                              ProfileNameStore.instance.nameFor(
                                userId: user.uid,
                                googleName: user.displayName ?? '',
                              ),
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            email?.isNotEmpty == true
                                ? email!
                                : 'Email unavailable',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              key: const ValueKey('edit-profile-name-button'),
                              onPressed: () => _editName(user),
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Edit Name'),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxl),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _isSigningOut ? null : _signOut,
                              icon: _isSigningOut
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.logout),
                              label: const Text('Sign Out'),
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
        },
      ),
    );
  }
}
