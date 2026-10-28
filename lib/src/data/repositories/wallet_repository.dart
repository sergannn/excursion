import '../../core/api/api_client.dart';
import '../../core/api/api_helpers.dart';
import '../models/wallet.dart';
import '../models/profit.dart';

class WalletRepository {
  WalletRepository(this._client);

  final ApiClient _client;

  Future<WalletInfo> fetchWallet(int userId) async {
    final response = await _client.getJson(
      '/api/users/$userId/wallet',
      authenticated: true,
    );
    return WalletInfo.fromJson(response);
  }

  Future<SalesInfo> fetchSales(int userId) async {
    final response = await _client.getJson(
      '/api/users/$userId/sales',
      authenticated: true,
    );
    return SalesInfo.fromJson(response);
  }

  Future<ProfitInfo> fetchProfit(int userId) async {
    final response = await _client.getJson(
      '/api/users/$userId/profit',
      authenticated: true,
    );
    return ProfitInfo.fromJson(response);
  }

  Future<Map<String, dynamic>> fetchStaffProfit(int userId) async {
    final response = await _client.getJson(
      '/api/users/$userId/staff-profit',
      authenticated: true,
    );
    return response;
  }
}
