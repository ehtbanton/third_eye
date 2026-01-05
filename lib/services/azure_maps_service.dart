import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../models/route_info.dart';

class AzureMapsService {
  String? _subscriptionKey;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  Future<bool> initialize() async {
    try {
      _subscriptionKey = dotenv.env['AZURE_MAPS_SUBSCRIPTION_KEY'];
      if (_subscriptionKey == null ||
          _subscriptionKey!.isEmpty ||
          _subscriptionKey == 'your-azure-maps-subscription-key-here') {
        print('ERROR: AZURE_MAPS_SUBSCRIPTION_KEY not set in .env file');
        return false;
      }
      _isInitialized = true;
      print('AzureMapsService initialized successfully');
      return true;
    } catch (e) {
      print('Failed to initialize AzureMapsService: $e');
      return false;
    }
  }

  String getTileUrl() {
    if (!_isInitialized || _subscriptionKey == null) {
      throw Exception('AzureMapsService not initialized');
    }
    return 'https://atlas.microsoft.com/map/tile?api-version=2024-04-01&tilesetId=microsoft.base.road&zoom={z}&x={x}&y={y}&subscription-key=$_subscriptionKey';
  }

  Future<RouteInfo?> getRoute(LatLng origin, LatLng destination) async {
    if (!_isInitialized || _subscriptionKey == null) {
      print('AzureMapsService not initialized');
      return null;
    }

    try {
      final query = '${origin.latitude},${origin.longitude}:${destination.latitude},${destination.longitude}';
      final url = Uri.parse(
        'https://atlas.microsoft.com/route/directions/json'
        '?api-version=1.0'
        '&subscription-key=$_subscriptionKey'
        '&query=$query'
        '&travelMode=pedestrian'
        '&routeType=shortest'
        '&avoid=motorways'
        '&instructionsType=text'
      );
      print('Route URL: $url');

      print('Requesting route from Azure Maps...');
      final response = await http.get(url).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Route request timed out');
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return RouteInfo.fromAzureMapsResponse(data);
      } else {
        print('Azure Maps API error: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Failed to get route: $e');
      return null;
    }
  }
}
