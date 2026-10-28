import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../util/json.dart';
import 'sse.dart';

/// A failed API call, mapped from the server's problem+json body.
class ApiException implements Exception {
  ApiException({required this.status, required this.code, required this.message, this.fieldErrors = const {}, this.extra = const {}});

  final int status;
  final String code;
  final String message;
  final Map<String, String> fieldErrors;
  final Map<String, dynamic> extra;

  bool get isNetwork => status == 0;
  bool get isConsentRequired => code == 'consent_required';
  bool get isQuotaExceeded => code == 'quota_exceeded';
  bool get isUnauthorized => status == 401;

  factory ApiException.fromBody(int status, Object? body) {
    final map = body is Map ? obj(body) : (body is String ? _tryDecode(body) : const <String, dynamic>{});
    final errors = obj(map['errors']).map((k, v) => MapEntry(k, str(v)));
    final extra = Map<String, dynamic>.from(map)..removeWhere((k, _) => const {'type', 'title', 'status', 'code', 'detail', 'errors'}.contains(k));
    return ApiException(
      status: status,
      code: strOrNull(map['code']) ?? 'http_$status',
      message: strOrNull(map['detail']) ?? _defaultMessage(status),
      fieldErrors: errors,
      extra: extra,
    );
  }

  factory ApiException.network() => ApiException(
        status: 0,
        code: 'network',
        message: 'Can\'t reach Career Ops right now. Check your connection and try again.',
      );

  static Map<String, dynamic> _tryDecode(String text) {
    try {
      return obj(jsonDecode(text));
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  static String _defaultMessage(int status) {
    if (status == 401) return 'Your session has expired. Sign in again.';
    if (status == 404) return 'That item no longer exists.';
    if (status >= 500) return 'Something went wrong on our side. Please try again.';
    return 'The request could not be completed.';
  }

  @override
  String toString() => 'ApiException($status, $code): $message';
}

String friendlyError(Object error) {
  if (error is ApiException) return error.message;
  return 'Something unexpected happened. Please try again.';
}

/// Provides bearer tokens. `forceRefresh` is used once after a 401.
typedef TokenProvider = Future<String?> Function({bool forceRefresh});

class ApiClient {
  ApiClient({required String baseUrl, required TokenProvider tokens, required void Function() onUnauthorized, Dio? dio})
      : _tokens = tokens,
        _onUnauthorized = onUnauthorized,
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 15),
              sendTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 150),
              contentType: Headers.jsonContentType,
              responseType: ResponseType.json,
            ));

  final Dio _dio;
  final TokenProvider _tokens;
  final void Function() _onUnauthorized;

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) => _request('GET', path, query: query);
  Future<dynamic> post(String path, [Object? body]) => _request('POST', path, data: body);
  Future<dynamic> put(String path, [Object? body]) => _request('PUT', path, data: body);
  Future<dynamic> patch(String path, [Object? body]) => _request('PATCH', path, data: body);
  Future<dynamic> delete(String path, [Object? body]) => _request('DELETE', path, data: body);

  Future<String> getText(String path, {Map<String, dynamic>? query}) async {
    final data = await _request('GET', path, query: query, responseType: ResponseType.plain);
    return str(data);
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? query,
    ResponseType? responseType,
    bool retried = false,
  }) async {
    final token = await _tokens(forceRefresh: retried);
    try {
      final res = await _dio.request<dynamic>(
        path,
        data: data,
        queryParameters: query,
        options: Options(
          method: method,
          responseType: responseType,
          headers: {if (token != null) 'Authorization': 'Bearer $token'},
        ),
      );
      return res.data;
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      if (status == 401 && !retried) {
        return _request(method, path, data: data, query: query, responseType: responseType, retried: true);
      }
      if (status == 401) _onUnauthorized();
      if (status == 0) throw ApiException.network();
      throw ApiException.fromBody(status, e.response?.data);
    }
  }

  /// POST that answers with Server-Sent Events (assistant replies).
  Stream<SseEvent> postStream(String path, Object body) async* {
    final token = await _tokens(forceRefresh: false);
    Response<ResponseBody> res;
    try {
      res = await _dio.post<ResponseBody>(
        path,
        data: body,
        options: Options(
          responseType: ResponseType.stream,
          receiveTimeout: const Duration(minutes: 3),
          headers: {'Accept': 'text/event-stream', if (token != null) 'Authorization': 'Bearer $token'},
        ),
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      if (status == 0) throw ApiException.network();
      if (status == 401) _onUnauthorized();
      final raw = e.response?.data;
      String text = '';
      if (raw is ResponseBody) {
        text = await utf8.decodeStream(raw.stream);
      }
      throw ApiException.fromBody(status, text);
    }
    final stream = res.data?.stream;
    if (stream == null) return;
    yield* parseSse(stream.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()));
  }
}
