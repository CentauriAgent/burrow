import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:burrow_app/src/rust/api/relay.dart';

class RelayNotifier extends AsyncNotifier<List<RelayInfo>> {
  @override
  Future<List<RelayInfo>> build() async {
    try {
      return await listRelays();
    } catch (_) {
      return [];
    }
  }

  Future<void> addAndConnect(String url) async {
    await addRelay(url: url);
    await connectRelays();
    state = AsyncData(await listRelays());
  }

  Future<void> remove(String url) async {
    await removeRelay(url: url);
    state = AsyncData(await listRelays());
  }

  Future<void> refresh() async {
    state = AsyncData(await listRelays());
  }

  List<String> get defaultRelays => defaultRelayUrls();
}

final relayProvider =
    AsyncNotifierProvider<RelayNotifier, List<RelayInfo>>(() {
  return RelayNotifier();
});
