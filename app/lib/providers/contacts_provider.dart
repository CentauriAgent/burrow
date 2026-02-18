import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:burrow_app/src/rust/api/contacts.dart' as rust_contacts;

/// A Marmot-capable contact (NIP-02 follow with a published key package).
class Contact {
  final String pubkeyHex;
  final String? displayName;
  final String? picture;

  const Contact({required this.pubkeyHex, this.displayName, this.picture});

  /// Best name for display, falling back to truncated pubkey.
  String get name {
    if (displayName != null && displayName!.isNotEmpty) return displayName!;
    if (pubkeyHex.length > 16) {
      return '${pubkeyHex.substring(0, 8)}...${pubkeyHex.substring(pubkeyHex.length - 8)}';
    }
    return pubkeyHex;
  }

  /// Sort key: lowercase name for alphabetical sorting.
  String get sortKey => name.toLowerCase();
}

/// Contacts provider: loads from local cache instantly, syncs with relays
/// in the background on every app launch. Pull-to-refresh triggers a full sync.
class ContactsNotifier extends AsyncNotifier<List<Contact>> {
  @override
  Future<List<Contact>> build() async {
    List<rust_contacts.ContactInfo> cached;
    try {
      cached = await rust_contacts.getCachedContacts();
    } catch (_) {
      cached = [];
    }

    if (cached.isEmpty) {
      // No cache — do a full sync so the user sees a loading spinner
      try {
        final synced = await rust_contacts.syncContacts();
        return _toContacts(synced);
      } catch (_) {
        return [];
      }
    }

    // Cache exists — return it immediately, refresh in background
    _backgroundSync();
    return _toContacts(cached);
  }

  Future<void> _backgroundSync() async {
    try {
      final synced = await rust_contacts.syncContacts();
      state = AsyncData(_toContacts(synced));
    } catch (_) {
      // Silently fail — cached data is still showing
    }
  }

  /// Full relay sync, called by the sync button.
  Future<void> refresh() async {
    final previous = state.value;
    state = const AsyncLoading();
    try {
      final synced = await rust_contacts.syncContacts();
      state = AsyncData(_toContacts(synced));
    } catch (_) {
      // Restore previous data if available, otherwise show empty
      state = AsyncData(previous ?? []);
    }
  }

  List<Contact> _toContacts(List<rust_contacts.ContactInfo> infos) {
    final contacts = infos
        .map(
          (c) => Contact(
            pubkeyHex: c.pubkeyHex,
            displayName: c.displayName,
            picture: c.picture,
          ),
        )
        .toList();
    contacts.sort((a, b) => a.sortKey.compareTo(b.sortKey));
    return contacts;
  }
}

final contactsProvider = AsyncNotifierProvider<ContactsNotifier, List<Contact>>(
  ContactsNotifier.new,
);
