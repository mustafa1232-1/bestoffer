import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maslaki/features/games/data/games_api.dart';
import 'package:maslaki/features/games/state/knowledge_match_controller.dart';
import 'package:maslaki/features/games/ui/knowledge_game_screen.dart';

// Actual match screen and HTTP API against the opt-in loopback QA server.
// This is not a shipping entrypoint and contains no production credentials.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:4878'));
  final bracket = Uri.base.queryParameters['bracket'] == '1';
  final fixture = (await dio.get<Map<String, dynamic>>(
    bracket ? '/tournament' : '/fixture',
  )).data!;
  dio.options.headers['Authorization'] = 'Bearer ${fixture['token']}';
  runApp(
    ProviderScope(
      overrides: [
        gamesApiProvider.overrideWithValue(GamesApi(dio)),
        knowledgeRealtimeProvider.overrideWithValue(null),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          fontFamily: 'TajawalLocal',
          brightness: Brightness.light,
        ),
        home: bracket
            ? KnowledgeEventScreen(
                event: Map<String, dynamic>.from(fixture['event'] as Map),
              )
            : KnowledgeMatchScreen(
                matchId: (fixture['matchId'] as num).toInt(),
              ),
      ),
    ),
  );
}
