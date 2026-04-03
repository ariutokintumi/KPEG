import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const KpegApp());
}

class KpegApp extends StatelessWidget {
  const KpegApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KPEG App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00C896),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const PantallaInicio(),
    );
  }
}

class PantallaInicio extends StatefulWidget {
  const PantallaInicio({super.key});

  @override
  State<PantallaInicio> createState() => _PantallaInicioState();
}

class _PantallaInicioState extends State<PantallaInicio> {
  File? _fotoSeleccionada;
  EstadoEnvio _estado = EstadoEnvio.esperando;
  String _mensajeEstado = '';

  // 👇 IP especial del emulador para acceder al PC local
  static const String _urlApi = 'http://10.105.176.246:8000/upload';

  Future<void> _abrirCamara() async {
    final picker = ImagePicker();
    final XFile? foto = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (foto != null) {
      setState(() {
        _fotoSeleccionada = File(foto.path);
        _estado = EstadoEnvio.esperando;
        _mensajeEstado = '';
      });
    }
  }

  Future<void> _enviarFoto() async {
    if (_fotoSeleccionada == null) return;
    setState(() {
      _estado = EstadoEnvio.enviando;
      _mensajeEstado = 'Enviando foto...';
    });
    try {
      final request = http.MultipartRequest('POST', Uri.parse(_urlApi));
      request.files.add(
        await http.MultipartFile.fromPath('foto', _fotoSeleccionada!.path),
      );
      final respuesta = await request.send().timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw Exception('Tiempo de espera agotado'),
      );
      if (respuesta.statusCode == 200 || respuesta.statusCode == 201) {
        setState(() {
          _estado = EstadoEnvio.exito;
          _mensajeEstado = '¡Foto enviada correctamente! ✓';
        });
      } else {
        setState(() {
          _estado = EstadoEnvio.error;
          _mensajeEstado = 'Error del servidor: ${respuesta.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _estado = EstadoEnvio.error;
        _mensajeEstado = 'Error de conexión: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0A0A0A), Color(0xFF0D1F1A), Color(0xFF0A1628)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── Cabecera ──
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 36),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00C896).withOpacity(0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF00C896).withOpacity(0.4),
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.camera_alt_rounded,
                        size: 36,
                        color: Color(0xFF00C896),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'KPEG',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 6,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Captura y envía',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF00C896),
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Previsualización ──
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: _fotoSeleccionada == null
                      ? _vistaVacia()
                      : _vistaFoto(),
                ),
              ),

              // ── Botones ──
              Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  children: [
                    if (_mensajeEstado.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: _colorEstado().withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: _colorEstado().withOpacity(0.5)),
                        ),
                        child: Text(
                          _mensajeEstado,
                          style: TextStyle(
                              color: _colorEstado(), fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      ),

                    // Botón cámara
                    SizedBox(
                      width: double.infinity,
                      height: 58,
                      child: ElevatedButton.icon(
                        onPressed: _estado == EstadoEnvio.enviando
                            ? null
                            : _abrirCamara,
                        icon: const Icon(Icons.camera_alt_rounded),
                        label: Text(
                          _fotoSeleccionada == null
                              ? 'Hacer foto'
                              : 'Nueva foto',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00C896),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 8,
                          shadowColor:
                              const Color(0xFF00C896).withOpacity(0.4),
                        ),
                      ),
                    ),

                    // Botón enviar
                    if (_fotoSeleccionada != null) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 58,
                        child: OutlinedButton.icon(
                          onPressed: _estado == EstadoEnvio.enviando
                              ? null
                              : _enviarFoto,
                          icon: _estado == EstadoEnvio.enviando
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF00C896),
                                  ),
                                )
                              : const Icon(Icons.send_rounded),
                          label: Text(
                            _estado == EstadoEnvio.enviando
                                ? 'Enviando...'
                                : 'Enviar foto',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF00C896),
                            side: const BorderSide(
                                color: Color(0xFF00C896), width: 1.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _colorEstado() {
    switch (_estado) {
      case EstadoEnvio.exito:
        return Colors.green;
      case EstadoEnvio.error:
        return Colors.redAccent;
      default:
        return const Color(0xFF00C896);
    }
  }

  Widget _vistaVacia() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
            color: const Color(0xFF00C896).withOpacity(0.2), width: 1.5),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_a_photo_rounded,
                size: 64,
                color: const Color(0xFF00C896).withOpacity(0.3)),
            const SizedBox(height: 16),
            Text(
              'Pulsa el botón para\nhacer una foto',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.3), fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vistaFoto() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(_fotoSeleccionada!, fit: BoxFit.cover),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.4),
                ],
              ),
            ),
          ),
          if (_estado == EstadoEnvio.exito)
            Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.85),
                  shape: BoxShape.circle,
                ),
                child:
                    const Icon(Icons.check, size: 48, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

enum EstadoEnvio { esperando, enviando, exito, error }
