import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/seller_model.dart';
import '../../../core/services/mock_data_service.dart';

abstract class SellersRepository {
  Future<List<SellerModel>> getSellers();
}

class MockSellersRepository implements SellersRepository {
  @override
  Future<List<SellerModel>> getSellers() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return MockDataService.getSellers();
  }
}

final sellersRepositoryProvider = Provider<SellersRepository>((ref) {
  return MockSellersRepository();
});
