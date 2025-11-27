class BiltyTemplate {
  final String name, version, layout;
  final List<BiltySection> sections;

  BiltyTemplate({
    required this.name,
    required this.version,
    required this.layout,
    required this.sections,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'version': version,
    'layout': layout,
    'sections': sections.map((e) => e.toJson()).toList(),
  };

  factory BiltyTemplate.fromJson(Map<String, dynamic> json) => BiltyTemplate(
    name: json['name'] ?? '',
    version: json['version'] ?? '',
    layout: json['layout'] ?? '',
    sections: (json['sections'] as List? ?? [])
        .map((e) => BiltySection.fromJson(e))
        .toList(),
  );

  static BiltyTemplate get defaultTemplate => BiltyTemplate(
    name: "Professional Transport Bilty",
    version: "1.0",
    layout: "two_column_header",
    sections: _defaultSections,
  );

  static const _defaultSections = [
    BiltySection(
      sectionId: "header",
      type: "header",
      elements: [
        BiltyElement(
          id: "logo",
          type: "image_placeholder",
          label: "Company Logo",
        ),
        BiltyElement(
          id: "company_name",
          type: "static_text",
          content: "Transport Company Name",
          style: "h1",
        ),
        BiltyElement(
          id: "copy_type",
          type: "static_text",
          content: "Original - Consignor Copy",
          style: "watermark",
        ),
      ],
    ),

    BiltySection(
      sectionId: "primary_details",
      type: "grid",
      columns: 2,
      elements: [
        BiltyElement(id: "bilty_no", label: "Bilty No.:", type: "text_input"),
        BiltyElement(id: "date", label: "Date:", type: "date_picker"),
        BiltyElement(
          id: "sender_details",
          label: "Sender",
          type: "text_area",
          lines: 3,
        ),
        BiltyElement(id: "truck_no", label: "Truck No.", type: "text_input"),
        BiltyElement(
          id: "recipient_details",
          label: "Recipient",
          type: "text_area",
          lines: 3,
        ),
        BiltyElement(id: "from_where", label: "From", type: "text_input"),
        BiltyElement(
          id: "truck_owner_name",
          label: "Truck Owner",
          type: "text_input",
        ),
        BiltyElement(id: "till_where", label: "To", type: "text_input"),
        BiltyElement(id: "engine_no", label: "Engine No.", type: "text_input"),
        BiltyElement(id: "driver_name", label: "Driver", type: "text_input"),
        BiltyElement(id: "driver_phone", label: "Phone", type: "text_input"),
        BiltyElement(
          id: "driver_license",
          label: "License",
          type: "text_input",
        ),
        BiltyElement(
          id: "vehicle_type",
          label: "Vehicle Type",
          type: "text_input",
        ),
        BiltyElement(
          id: "transporter_name",
          label: "Transporter",
          type: "text_input",
        ),
        BiltyElement(
          id: "transporter_gstin",
          label: "GSTIN",
          type: "text_input",
        ),
        BiltyElement(
          id: "delivery_date",
          label: "Delivery Date",
          type: "date_picker",
        ),
      ],
    ),

    BiltySection(
      sectionId: "goods_and_charges",
      type: "table",
      label: "Goods & Charges",
      allowAddRow: true,
      tableColumns: [
        BiltyColumn(id: "sr_no", header: "#"),
        BiltyColumn(id: "description", header: "Description"),
        BiltyColumn(id: "weight", header: "Weight (kg)"),
        BiltyColumn(id: "qty", header: "Qty"),
        BiltyColumn(id: "rate", header: "Rate (₹)"),
        BiltyColumn(id: "amount", header: "Amount (₹)"),
      ],
      elements: [],
    ),

    BiltySection(
      sectionId: "charges",
      type: "grid",
      columns: 2,
      elements: [
        BiltyElement(
          id: "basic_fare",
          label: "Basic Fare",
          type: "number_input",
        ),
        BiltyElement(
          id: "other_charges",
          label: "Other Charges",
          type: "number_input",
        ),
        BiltyElement(id: "gst", label: "GST", type: "number_input"),
        BiltyElement(
          id: "total_amount",
          label: "Total Amount",
          type: "number_input",
          readOnly: true,
        ),
        BiltyElement(
          id: "payment_status",
          label: "Payment Status",
          type: "dropdown",
          options: ["Paid", "To Pay", "Partial"],
        ),
      ],
    ),

    BiltySection(
      sectionId: "remarks",
      type: "single",
      elements: [
        BiltyElement(
          id: "remarks",
          label: "Remarks",
          type: "text_area",
          lines: 3,
        ),
      ],
    ),
  ];
}

class BiltySection {
  final String sectionId, type;
  final int? columns;
  final String? label;
  final bool? allowAddRow;
  final List<BiltyElement> elements;
  final List<BiltyColumn>? tableColumns;

  const BiltySection({
    required this.sectionId,
    required this.type,
    this.columns,
    this.label,
    this.elements = const [],
    this.tableColumns,
    this.allowAddRow,
  });

  Map<String, dynamic> toJson() => {
    'section_id': sectionId,
    'type': type,
    'columns': columns,
    'label': label,
    'allow_add_row': allowAddRow,
    'elements': elements.map((e) => e.toJson()).toList(),
    'table_columns': tableColumns?.map((e) => e.toJson()).toList(),
  };

  factory BiltySection.fromJson(Map<String, dynamic> json) => BiltySection(
    sectionId: json['section_id'] ?? '',
    type: json['type'] ?? '',
    columns: json['columns'],
    label: json['label'],
    allowAddRow: json['allow_add_row'],
    elements: (json['elements'] as List? ?? [])
        .map((e) => BiltyElement.fromJson(e))
        .toList(),
    tableColumns: (json['table_columns'] as List? ?? [])
        .map((e) => BiltyColumn.fromJson(e))
        .toList(),
  );
}

class BiltyElement {
  final String id, type;
  final String? label, content, placeholder, style;
  final int? lines;
  final bool? readOnly;
  final List<String>? options;
  final List<BiltyOption>? checkboxOptions;
  final List<BiltyElement>? groupElements;

  const BiltyElement({
    required this.id,
    required this.type,
    this.label,
    this.content,
    this.placeholder,
    this.style,
    this.lines,
    this.readOnly,
    this.options,
    this.checkboxOptions,
    this.groupElements,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'label': label,
    'content': content,
    'placeholder': placeholder,
    'style': style,
    'lines': lines,
    'read_only': readOnly,
    'options': options,
    'checkbox_options': checkboxOptions?.map((e) => e.toJson()).toList(),
    'group_elements': groupElements?.map((e) => e.toJson()).toList(),
  };

  factory BiltyElement.fromJson(Map<String, dynamic> json) => BiltyElement(
    id: json['id'] ?? '',
    type: json['type'] ?? '',
    label: json['label'],
    content: json['content'],
    placeholder: json['placeholder'],
    style: json['style'],
    lines: json['lines'],
    readOnly: json['read_only'],
    options: (json['options'] as List?)?.cast<String>(),
    checkboxOptions: (json['checkbox_options'] as List? ?? [])
        .map((e) => BiltyOption.fromJson(e))
        .toList(),
    groupElements: (json['group_elements'] as List? ?? [])
        .map((e) => BiltyElement.fromJson(e))
        .toList(),
  );
}

class BiltyColumn {
  final String id, header;
  const BiltyColumn({required this.id, required this.header});
  Map<String, dynamic> toJson() => {'id': id, 'header': header};
  factory BiltyColumn.fromJson(Map<String, dynamic> json) =>
      BiltyColumn(id: json['id'] ?? '', header: json['header'] ?? '');
}

class BiltyOption {
  final String id, label;
  const BiltyOption({required this.id, required this.label});
  Map<String, dynamic> toJson() => {'id': id, 'label': label};
  factory BiltyOption.fromJson(Map<String, dynamic> json) =>
      BiltyOption(id: json['id'] ?? '', label: json['label'] ?? '');
}