class BusinessProfile {
  final String name;
  final String address;
  final String phone;
  final String rfc;
  final String ticketHeader;
  final String ticketFooter;

  BusinessProfile({
    this.name = 'Mi Tiendita Tabapagos',
    this.address = 'Mercado Local, México',
    this.phone = '55 1234 5678',
    this.rfc = 'XAXX010101000',
    this.ticketHeader = '¡Gracias por apoyar el comercio local!',
    this.ticketFooter = 'Conserve su ticket para cualquier duda',
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'address': address,
      'phone': phone,
      'rfc': rfc,
      'ticket_header': ticketHeader,
      'ticket_footer': ticketFooter,
    };
  }

  factory BusinessProfile.fromMap(Map<String, dynamic> map) {
    return BusinessProfile(
      name: map['name'] as String? ?? 'Mi Tiendita Tabapagos',
      address: map['address'] as String? ?? 'Mercado Local, México',
      phone: map['phone'] as String? ?? '55 1234 5678',
      rfc: map['rfc'] as String? ?? 'XAXX010101000',
      ticketHeader: map['ticket_header'] as String? ?? '¡Gracias por apoyar el comercio local!',
      ticketFooter: map['ticket_footer'] as String? ?? 'Conserve su ticket para cualquier duda',
    );
  }
}
