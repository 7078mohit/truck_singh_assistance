import 'dart:io';
import 'package:flutter/material.dart';
import 'package:logistics_toolkit/config/theme.dart';
import 'package:pdfx/pdfx.dart';

class BiltyPdfPreviewScreen extends StatefulWidget {
  final String localPath;

  const BiltyPdfPreviewScreen({super.key, required this.localPath});

  @override
  State<BiltyPdfPreviewScreen> createState() => _BiltyPdfPreviewScreenState();
}

class _BiltyPdfPreviewScreenState extends State<BiltyPdfPreviewScreen> {
  late PdfControllerPinch _pdfController;

  @override
  void initState() {
    super.initState();
    _pdfController = PdfControllerPinch(
      document: PdfDocument.openFile(widget.localPath),
    );
  }

  @override
  void dispose() {
    _pdfController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.lightTheme,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Bilty Preview',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white),
          ),
        ),
        body: SafeArea(
          child: PdfViewPinch(
            controller: _pdfController,
            scrollDirection: Axis.vertical,
          ),
        ),
      ),
    );
  }
}