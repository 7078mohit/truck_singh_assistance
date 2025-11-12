import 'package:flutter/material.dart';
import 'package:logistics_toolkit/config/theme.dart';
import 'package:printing/printing.dart';
import 'dart:io';


class PdfPreviewPage extends StatelessWidget {
  final File pdfFile;

  PdfPreviewPage({required this.pdfFile});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            "PDF Preview",
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white),
          ),
        ),
        body: SafeArea(
          child: PdfPreview(
            build: (format) async => pdfFile.readAsBytes(),
          ),
        ),
      ),
    );
  }
}