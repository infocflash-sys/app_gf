class AppConfig {
  /// URL de la API. En el emulador de Android, 10.0.2.2 apunta a la PC.
  /// En un celular real: flutter run --dart-define=API_URL=http://IP_DE_LA_PC:3000
  static const apiUrl =
      String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:3000');

  static const webComercial = 'www.flashlogistica.com.ar';
}
