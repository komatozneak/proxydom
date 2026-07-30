import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/beta_api.dart';
import '../data/beta_usage_aggregate_store.dart';

final betaApiProvider = Provider<BetaApi>((ref) => BetaApi());

final betaUsageStoreProvider = Provider<BetaUsageAggregateStore>(
  (ref) => BetaUsageAggregateStore(),
);
