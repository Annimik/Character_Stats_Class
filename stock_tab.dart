import 'package:flutter/material.dart';
import 'package:test_build_1/services/inventory_service.dart';

class StockTab extends StatefulWidget {
  final InventoryService inventory;
  const StockTab({super.key, required this.inventory});

  @override
  State<StockTab> createState() => _StockTabState();
}

class _StockTabState extends State<StockTab> {
  late Future<List<StockLine>> future;

  @override
  void initState() {
    super.initState();
    future = widget.inventory.listStock();
  }

  Future<void> reload() async {
    setState(() => future = widget.inventory.listStock());
    await future;
  }

  String _mmToMetersLabel(int mm) {
    if (mm % 1000 == 0) return '${mm ~/ 1000} м';
    return '${mm / 1000} м';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<StockLine>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Ошибка: ${snap.error}'),
            ),
          );
        }

        final items = snap.data ?? const <StockLine>[];
        if (items.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                'Пока нет позиций.\nДобавь товар и сделай приход.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: reload,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final line = items[i];
              final p = line.product;

              return Card(
                child: ListTile(
                  title: Text(
                    '${p.code} • ${p.name}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text('Ø ${p.diameterMm} мм • ${_mmToMetersLabel(p.lengthMm)}'),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('На складе', style: TextStyle(fontSize: 12)),
                      Text(
                        '${line.quantity} шт',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
