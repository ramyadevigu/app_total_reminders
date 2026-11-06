import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class GoogleProfileAvatar extends StatelessWidget {
  const GoogleProfileAvatar({
    super.key,
    required this.user,
    required this.radius,
  });

  final User user;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final photoUrl = user.photoURL;
    return CircleAvatar(
      radius: radius,
      backgroundColor: colorScheme.secondaryContainer,
      child: photoUrl == null || photoUrl.isEmpty
          ? Icon(
              Icons.person_outline,
              color: colorScheme.onSecondaryContainer,
              size: radius,
            )
          : ClipOval(
              child: Image.network(
                photoUrl,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.person_outline,
                  color: colorScheme.onSecondaryContainer,
                  size: radius,
                ),
              ),
            ),
    );
  }
}
