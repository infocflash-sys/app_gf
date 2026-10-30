import 'package:flutter_test/flutter_test.dart';
import 'package:grupo_flash_portal/data/models.dart';

void main() {
  test('Piece.fromJson: estado definitivo = azul, en gestión = verde', () {
    final fin = Piece.fromJson({
      'id': 212991, 'tracking': '212991', 'destinatario': ' Ana ', 'localidad': 'Salta',
      'cantidad': 1, 'estado': 'Entregado', 'definitivo': true, 'fecha': '2026-08-07T16:03:00-03:00',
    });
    expect(fin.definitivo, isTrue);
    expect(fin.destinatario, 'Ana');
    expect(fin.fecha, isNotNull);

    final ges = Piece.fromJson({'id': 1, 'estado': 'Pendiente de Recepción', 'definitivo': false});
    expect(ges.definitivo, isFalse);
    expect(ges.tracking, '1'); // sin tracking usa el id
  });

  test('PieceDetail.fromJson: eventos con foto y firma, y PDF', () {
    final d = PieceDetail.fromJson({
      'id': 191610, 'estado': 'Entregado', 'definitivo': true, 'domicilio': 'Calle 1', 'bultos': 2,
      'pesoKg': 3.5, 'pdf': true,
      'eventos': [
        {'id': 9, 'estado': 'Entregado', 'definitivo': true, 'fecha': '2026-08-07T16:03:00-03:00', 'foto': true, 'firma': false},
        {'id': 8, 'estado': 'En distribucion', 'definitivo': false, 'fecha': '2026-08-07T12:55:00-03:00', 'foto': false, 'firma': false},
      ],
    });
    expect(d.pdf, isTrue);
    expect(d.eventos.length, 2);
    expect(d.eventos.first.foto, isTrue);
    expect(d.eventos.first.firma, isFalse);
    expect(d.pesoKg, 3.5);
  });

  test('PiecePage.fromJson con resumen', () {
    final p = PiecePage.fromJson({
      'items': [], 'hasMore': true,
      'resumen': {'total': 3, 'finalizadas': 1, 'enGestion': 2, 'dias': 30},
    });
    expect(p.hasMore, isTrue);
    expect(p.resumen!.enGestion, 2);
  });

  test('Profile usa el nombre del cliente', () {
    final pr = Profile.fromJson({'cliente': 'ACME SA ', 'clientes': [{'id': 1, 'nombre': 'ACME SA '}]});
    expect(pr.cliente, 'ACME SA');
    expect(Profile.fromJson(pr.toJson()).clientes, ['ACME SA']);
  });
}
