import 'package:flutter/widgets.dart';

class AppStrings {
  const AppStrings(this.locale);

  final Locale locale;

  bool get isJapanese => locale.languageCode == 'ja';

  static AppStrings of(BuildContext context) {
    return Localizations.of<AppStrings>(context, AppStrings) ??
        const AppStrings(Locale('en'));
  }

  static const delegate = _AppStringsDelegate();

  String t(String ja) {
    if (isJapanese) return ja;
    return _en[ja] ?? ja;
  }

  static const _en = {
    'ホーム': 'Home',
    'イートログ': 'Eat Log',
    'AI相談': 'AI Chat',
    '設定': 'Settings',
    '身体情報': 'Profile',
    '食事ログをもとに、次の食事やPFCバランスを一緒に考えます。':
        'I can help think through your next meal and PFC balance from your meal log.',
    'モデルをリセット': 'Reset model',
    '次の食事を相談': 'Ask About Next Meal',
    '食事ログから相談': 'Ask From Meal Log',
    '今日の摂取量や直近の食事をもとに、次の食事を相談できます。':
        'Ask for meal ideas based on today\'s intake and recent meals.',
    '音声ON': 'Voice On',
    '音声OFF': 'Voice Off',
    '次の食事を提案': 'Suggest Next Meal',
    '今日の不足を確認': 'Check Today\'s Gaps',
    'PFCを整えたい': 'Balance PFC',
    '軽めにしたい': 'Keep It Light',
    '食事ログが増えるほど、提案は具体的になります。':
        'Suggestions get more specific as your meal log grows.',
    '例: コンビニで買える夕食を提案して': 'Example: Suggest a convenience-store dinner',
    '送信': 'Send',
    '読み上げ': 'Read Aloud',
    '提案を生成できませんでした。': 'Could not generate a suggestion.',
    'ダークモード': 'Dark Mode',
    '黒ベースのUIテーマに切り替えます': 'Switch to a dark UI theme.',
    '読み上げ音声': 'Read-Aloud Voice',
    '音声一覧を更新': 'Refresh Voices',
    '端末のデフォルト音声': 'Device Default Voice',
    '端末に追加の日本語音声が見つからない場合は、Androidの音声合成設定から追加できます。':
        'If no additional Japanese voices are available, add them in Android text-to-speech settings.',
    '通信が必要な音声は表示せず、端末内で使える日本語音声だけを表示します。性別情報は端末側で標準化されていません。':
        'Only offline Japanese voices available on this device are shown. Gender labels are not standardized by Android.',
    'こんにちは。Gemma Biteの読み上げ音声テストです。':
        'Hello. This is a Gemma Bite read-aloud voice test.',
    '試聴': 'Preview',
    '言語': 'Language',
    '端末設定に従います': 'Follow the device language setting.',
    'システム設定': 'System Default',
    '日本語': 'Japanese',
    'English': 'English',
    'モデルを確認しています': 'Checking model',
    'モデルを読み込んでいます': 'Loading model',
    '初回読み込みには時間がかかります。': 'The first load may take a while.',
    'モデルファイルが見つかりません': 'Model file not found',
    'モデルファイル (.litertlm) を配置してください:': 'Place a model file (.litertlm) here:',
    '読み込み中...': 'Loading...',
    'モデルを再検索': 'Search Again',
    '読み込むモデルを選択してください': 'Choose a model to load',
    '昨日の食事の記録': 'Yesterday\'s Meal Log',
    '今日の食事の記録': 'Today\'s Meal Log',
    '昨日の摂取量': 'Yesterday\'s Intake',
    '今日の摂取量': 'Today\'s Intake',
    '写真登録数': 'Photos Logged',
    'カロリー': 'Calories',
    '総カロリー': 'Total Calories',
    'タンパク質': 'Protein',
    '脂質': 'Fat',
    '炭水化物': 'Carbs',
    '塩分': 'Salt',
    'カフェイン': 'Caffeine',
    'アルコール': 'Alcohol',
    '過去7日間': 'Past 7 Days',
    '摂取カロリーの1日平均': 'Daily Average Calories',
    '写真投稿数': 'Photos Logged',
    '各日の摂取カロリー': 'Daily Calories',
    '食事の写真を撮影・選択してください': 'Take or select meal photos',
    '撮影': 'Camera',
    '選択': 'Select',
    '分析': 'Analyze',
    '未選択': 'Not selected',
    '投機デコードON': 'Speculative decoding ON',
    'まだ食事記録がありません': 'No meal records yet',
    'この期間の食事記録はありません': 'No meal records in this period',
    'PFCバランス': 'PFC Balance',
    'PFCバランスの推移': 'PFC Balance Trend',
    'P/F/Cの摂取エネルギー比': 'P/F/C energy ratio',
    '合計': 'Total',
    '一日の平均': 'Daily Average',
    'P タンパク質': 'P Protein',
    'F 脂質': 'F Fat',
    'C 炭水化物': 'C Carbs',
    '身体情報を入力': 'Enter Profile',
    '身長 cm': 'Height cm',
    '体重 kg': 'Weight kg',
    '推移': 'Trend',
    '生年月日': 'Birth Date',
    '生年月日を選択': 'Select Birth Date',
    '性別': 'Sex',
    '男': 'Male',
    '女': 'Female',
    '無回答': 'Prefer not to say',
    '特記事項': 'Notes',
    'あとで': 'Later',
    '保存': 'Save',
    '体重の推移': 'Weight Trend',
    '入力履歴': 'History',
    '食事詳細': 'Meal Details',
    'Gemmaとの確認': 'Clarify With Gemma',
    '成分表画像を選択': 'Select Nutrition Label',
    '撮影して添付': 'Take and Attach',
    '添付を外す': 'Remove Attachment',
    '例: ご飯は小盛り、味噌汁あり（画像添付のみでも可）':
        'Example: Small rice, with miso soup (image-only is OK)',
    'この食事を削除': 'Delete This Meal',
    'この食事を削除しますか？': 'Delete this meal?',
    '削除すると、食事ログと栄養集計からこの記録が取り除かれます。':
        'Deleting it removes this record from your meal log and nutrition totals.',
    'キャンセル': 'Cancel',
    '削除': 'Delete',
    '食事を削除しました。': 'Meal deleted.',
    '未取得': 'Unavailable',
    '開く': 'Open',
  };
}

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();

  @override
  bool isSupported(Locale locale) {
    return locale.languageCode == 'ja' || locale.languageCode == 'en';
  }

  @override
  Future<AppStrings> load(Locale locale) async {
    return AppStrings(
      locale.languageCode == 'ja' ? const Locale('ja') : const Locale('en'),
    );
  }

  @override
  bool shouldReload(_AppStringsDelegate old) => false;
}
