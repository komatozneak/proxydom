import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'config.dart';
import 'hmac_interceptor.dart';
import 'jwt_interceptor.dart';
import 'token_storage.dart';
import 'v2_path_interceptor.dart';

/// Единый экземпляр Dio с предустановленными интерсепторами.
class ApiClient {
  ApiClient._();

  static final Dio instance = _build();
  static Dio? _refreshClient;

  static bool isControlPlaneHost(String host) {
    final h = host.trim().toLowerCase();
    return h == 'api.teremokconnect.online' ||
        h == 'api2.teremokconnect.online' ||
        h == 'teremokconnect.online' ||
        h.endsWith('.teremokconnect.online');
  }

  /// Discovery failover: switch Dio base to `{origin}/v2` (or legacy `/api/v1`).
  static void setBaseOrigin(String origin) {
    final base = AppConfig.baseUrlForOrigin(origin);
    instance.options.baseUrl = base;
    _refreshClient?.options.baseUrl = base;
  }

  static Dio _build() {
    final refreshClient = Dio(
      BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: AppConfig.connectTimeout,
        receiveTimeout: AppConfig.receiveTimeout,
        contentType: 'application/json',
        responseType: ResponseType.json,
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    _refreshClient = refreshClient;
    _pinControlPlaneDns(refreshClient);

    final dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: AppConfig.connectTimeout,
        receiveTimeout: AppConfig.receiveTimeout,
        contentType: 'application/json',
        responseType: ResponseType.json,
        // 4xx обрабатываем сами (для refresh-логики), 5xx — как ошибки
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    _pinControlPlaneDns(dio);

    dio.interceptors.add(V2PathInterceptor());
    dio.interceptors.add(HmacSignatureInterceptor());

    dio.interceptors.add(
      JwtRefreshInterceptor(
        dio: dio,
        refreshEndpoint: 'auth/refresh',
        tokenStorage: TokenStorage.instance,
        refreshClient: refreshClient,
      ),
    );

    dio.interceptors.add(
      LogInterceptor(
        requestBody: false,
        // Temporary debug: need statusCode / content-type evidence.
        responseBody: false,
        requestHeader: false,
        responseHeader: true,
        logPrint: (obj) {
          // ignore: avoid_print
          print(obj);
        },
      ),
    );

    return dio;
  }

  /// VPN TUN DNS sometimes fails host lookup for the API hostname even though
  /// the control-plane IP is excludeRoute'd.
  ///
  /// IMPORTANT: for `https:` [HttpClient.connectionFactory] must return a
  /// [SecureSocket] (or ConnectionTask thereof). A plain [Socket] makes Dio
  /// send cleartext HTTP to :8443 → Caddy `400 Bad Request` (non-JSON body),
  /// which the gate shows as «Не удалось проверить доступ».
  static void _pinControlPlaneDns(Dio dio) {
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.connectionFactory = (uri, proxyHost, proxyPort) async {
          if (proxyHost != null && proxyPort != null) {
            return Socket.startConnect(proxyHost, proxyPort);
          }
          final InternetAddress address;
          if (isControlPlaneHost(uri.host)) {
            address = InternetAddress(AppConfig.vpsIpv4);
          } else {
            final lookedUp = await InternetAddress.lookup(uri.host);
            if (lookedUp.isEmpty) {
              throw const SocketException('Failed host lookup');
            }
            address = lookedUp.first;
          }
          if (uri.isScheme('https')) {
            // Connect TCP to pinned IP, then TLS with SNI/cert = uri.host.
            return _startSecureConnect(
              address: address,
              port: uri.port,
              sniHost: uri.host,
            );
          }
          return Socket.startConnect(address, uri.port);
        };
        return client;
      },
    );
  }

  /// [ConnectionTask] that upgrades a raw TCP connect to [SecureSocket].
  static Future<ConnectionTask<Socket>> _startSecureConnect({
    required InternetAddress address,
    required int port,
    required String sniHost,
  }) async {
    final rawTask = await Socket.startConnect(address, port);
    return ConnectionTask.fromSocket(
      rawTask.socket.then((raw) {
        return SecureSocket.secure(
          raw,
          host: sniHost,
        );
      }),
      rawTask.cancel,
    );
  }

  /// POST с увеличенным таймаутом для flash-call (Zvonok на backend).
  static Future<Response<dynamic>> postAuth(
    String path, {
    Object? data,
  }) {
    return instance.post(
      path,
      data: data,
      options: Options(
        connectTimeout: AppConfig.authConnectTimeout,
        receiveTimeout: AppConfig.authReceiveTimeout,
      ),
    );
  }
}
