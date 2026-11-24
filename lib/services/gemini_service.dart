import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/food_item.dart';

class GeminiService {
  static Uri _endpoint(String apiKey) => Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${Uri.encodeComponent(apiKey)}',
      );

  static Future<Map<String, dynamic>> analyzeFreshFood(String apiKey, String base64Jpeg) async {
    final today = todayDateStr();
    final prompt =
        '오늘 날짜는 $today입니다. 사진 속 채소·과일·육류·식자재의 이름과 상태를 파악하여, '
        '오늘($today) 기준으로 며칠 이내에 섭취해야 괜찮은지(recommendedDays)와 최적 보관 방법을 알려주세요. '
        '반드시 아래 JSON 형식으로만 응답하세요:\n'
        '{"name":"식자재명","emoji":"이모지","zone":"fridge 또는 freezer 또는 room","recommendedDays":5,"tip":"구체적인 보관 팁 한두문장","memo":"상태 메모","estimatedPrice":3500}';
    return _callVision(apiKey, prompt, base64Jpeg);
  }

  static Future<Map<String, dynamic>> scanExpiryOcr(String apiKey, String base64Jpeg) async {
    final today = todayDateStr();
    final prompt =
        '오늘 날짜는 $today입니다. 사진 속 기성품의 품목명과 포장지에 인쇄된 소비기한(또는 유통기한) 날짜를 YYYY-MM-DD 형식으로 읽고 보관법을 알려주세요. '
        '반드시 아래 JSON 형식으로만 응답하세요:\n'
        '{"name":"제품명","emoji":"이모지","zone":"fridge 또는 freezer 또는 room","expiryDate":"YYYY-MM-DD","tip":"보관 팁 한문장","estimatedPrice":3500}';
    return _callVision(apiKey, prompt, base64Jpeg);
  }

  static Future<List<BatchDraftItem>> scanReceiptBatch(String apiKey, String base64Jpeg) async {
    final today = todayDateStr();
    final prompt =
        '오늘 날짜는 $today입니다. 이 마트 영수증 사진에서 먹을 수 있는 식자재만 추출하세요. '
        '종량제봉투, 키친타월, 세제 등 비식자재는 제외하세요. 반드시 아래 JSON 형식으로만 응답하세요:\n'
        '{"items":[{"name":"품목명","emoji":"이모지","zone":"fridge 또는 freezer 또는 room","days":5,"tip":"핵심보관법 한문장","estimatedPrice":3500}]}';

    final res = await _callVision(apiKey, prompt, base64Jpeg);
    final rawItems = res['items'];
    if (rawItems is! List) return [];
    return rawItems.whereType<Map>().map((m) {
      final days = (m['days'] as num?)?.toInt() ?? 5;
      final zone = m['zone']?.toString() ?? 'fridge';
      return BatchDraftItem(
        checked: true,
        name: m['name']?.toString() ?? '식자재',
        emoji: m['emoji']?.toString() ?? '🥗',
        zone: (zone == 'freezer' || zone == 'room') ? zone : 'fridge',
        expiryDate: addDaysStr(today, days.clamp(1, 180)),
        tip: m['tip']?.toString() ?? '신선도에 유의해 밀폐 보관하세요.',
        estimatedPrice: (m['estimatedPrice'] as num?)?.toInt() ?? 3500,
      );
    }).toList();
  }

  static Future<List<RecipeSuggestion>> generateDinnerRecipes({
    required String apiKey,
    required List<String> ingredientNames,
    required String timePref,
    required String stylePref,
  }) async {
    final prompt =
        '보유 식자재: ${ingredientNames.join(', ')}\n'
        '선호 조리시간: $timePref, 요리 스타일: $stylePref.\n'
        '위 보유 식자재를 최대한 활용하여 오늘 저녁에 만들 수 있는 현실적이고 맛있는 한국 가정식 레시피 3가지를 추천해 주세요. '
        '반드시 아래 JSON 형식으로만 응답하세요:\n'
        '{"recipes":[{"title":"요리명","time":"소요시간","style":"스타일","summary":"한줄소개","usedNames":["사용된 보유식자재명"],"extraIngredients":["기본양념"],"steps":["1단계","2단계","3단계"]}]}';

    final response = await http.post(
      _endpoint(apiKey),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ],
        'generationConfig': {
          'response_mime_type': 'application/json',
          'temperature': 0.5,
        }
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Gemini API Error: ${response.statusCode}');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final rawText = decoded['candidates']?[0]?['content']?['parts']?[0]?['text']?.toString() ?? '{}';
    final parsed = jsonDecode(rawText) as Map<String, dynamic>;
    final list = parsed['recipes'];
    if (list is! List) return [];

    return list.whereType<Map>().map((r) {
      return RecipeSuggestion(
        title: r['title']?.toString() ?? '추천 집밥 메뉴',
        time: r['time']?.toString() ?? timePref,
        style: r['style']?.toString() ?? stylePref,
        summary: r['summary']?.toString() ?? '',
        usedNames: (r['usedNames'] as List?)?.map((e) => e.toString()).toList() ?? ingredientNames,
        extraIngredients: (r['extraIngredients'] as List?)?.map((e) => e.toString()).toList() ?? [],
        steps: (r['steps'] as List?)?.map((e) => e.toString()).toList() ?? [],
      );
    }).toList();
  }

  static Future<Map<String, dynamic>> _callVision(
    String apiKey,
    String prompt,
    String base64Jpeg,
  ) async {
    final response = await http.post(
      _endpoint(apiKey),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt},
              {
                'inline_data': {
                  'mime_type': 'image/jpeg',
                  'data': base64Jpeg,
                }
              }
            ]
          }
        ],
        'generationConfig': {
          'response_mime_type': 'application/json',
          'temperature': 0.2,
        }
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Gemini Vision Error (${response.statusCode})');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final rawText = decoded['candidates']?[0]?['content']?['parts']?[0]?['text']?.toString() ?? '{}';
    return jsonDecode(rawText) as Map<String, dynamic>;
  }
}
