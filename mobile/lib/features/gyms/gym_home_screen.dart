import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/auth.dart';
import '../../state/providers.dart';
import '../../state/session_controller.dart';
import '../../ui/widgets/common.dart';
import 'gym_detail_screen.dart';
import 'gym_search_screen.dart';

/// Pantalla raíz con sesión: los boulders del usuario.
///
/// Materializa el KPI multi-boulder — un mismo setter puede estar vinculado a
/// varios boulders a la vez.
class GymHomeScreen extends ConsumerWidget {
  const GymHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();

    final memberships = user.memberships;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis boulders'),
        actions: [
          IconButton(
            tooltip: 'Buscar boulders',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const GymSearchScreen()),
            ),
          ),
          PopupMenuButton<String>(
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'profile',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline),
                  title: Text(user.shownName),
                  subtitle: Text(user.email),
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.logout),
                  title: Text('Cerrar sesión'),
                ),
              ),
            ],
            onSelected: (value) {
              if (value == 'logout') {
                ref.read(sessionProvider.notifier).logout();
              }
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const GymFormScreen()),
        ),
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Registrar boulder'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(sessionProvider.notifier).reload(),
        child: memberships.isEmpty
            ? ListView(
                children: [
                  SizedBox(height: MediaQuery.sizeOf(context).height * 0.15),
                  EmptyState(
                    icon: Icons.terrain_outlined,
                    title: 'Todavía no estás en ningún boulder',
                    message:
                        'Registra el tuyo o busca uno existente para pedir acceso como setter.',
                    action: FilledButton.tonalIcon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const GymSearchScreen()),
                      ),
                      icon: const Icon(Icons.search),
                      label: const Text('Buscar boulders'),
                    ),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount: memberships.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) =>
                    _MembershipCard(membership: memberships[index]),
              ),
      ),
    );
  }
}

class _MembershipCard extends StatelessWidget {
  const _MembershipCard({required this.membership});

  final GymMembership membership;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authorized = membership.isAuthorized;

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: authorized
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          child: Icon(
            authorized ? Icons.terrain_rounded : Icons.hourglass_top_rounded,
            color: authorized
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.outline,
          ),
        ),
        title: Text(membership.gymName),
        subtitle: Row(
          children: [
            Chip(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              label: Text(membership.status.label),
            ),
            if (membership.isGymAdmin) ...[
              const SizedBox(width: 6),
              const Chip(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                label: Text('Admin'),
              ),
            ],
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: authorized
            ? () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GymDetailScreen(
                      gymId: membership.gymId,
                      gymName: membership.gymName,
                      isAdmin: membership.isGymAdmin,
                    ),
                  ),
                )
            : null,
      ),
    );
  }
}

/// Registro de un boulder — RF-1.1, RF-1.2, US-01.
class GymFormScreen extends ConsumerStatefulWidget {
  const GymFormScreen({super.key});

  @override
  ConsumerState<GymFormScreen> createState() => _GymFormScreenState();
}

class _GymFormScreenState extends ConsumerState<GymFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _country = TextEditingController(text: 'Colombia');
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _monthly = TextEditingController();
  final _daily = TextEditingController();

  bool _saving = false;

  @override
  void dispose() {
    for (final c in [
      _name,
      _address,
      _city,
      _country,
      _phone,
      _email,
      _monthly,
      _daily
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      // `pricing_plans` es JSONB: estructura libre por diseño (RF-1.2).
      final plans = <String, dynamic>{
        if (_monthly.text.trim().isNotEmpty)
          'mensual': num.tryParse(_monthly.text.trim()),
        if (_daily.text.trim().isNotEmpty)
          'dia': num.tryParse(_daily.text.trim()),
      };

      await ref.read(gymsRepositoryProvider).create(
            name: _name.text.trim(),
            address: _address.text.trim(),
            city: _city.text.trim(),
            country: _country.text.trim(),
            phone: _phone.text.trim(),
            email: _email.text.trim(),
            pricingPlans: plans.isEmpty ? null : plans,
          );

      // El access token vigente aún no lleva la nueva membresía: se renueva.
      await ref.read(sessionProvider.notifier).reload();

      if (!mounted) return;
      Navigator.of(context).pop();
      showInfo(context, 'Boulder registrado. Ya eres su administrador.');
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar boulder')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Nombre *'),
              validator: _required,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              decoration: const InputDecoration(labelText: 'Dirección *'),
              validator: _required,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _city,
                    decoration: const InputDecoration(labelText: 'Ciudad *'),
                    validator: _required,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _country,
                    decoration: const InputDecoration(labelText: 'País *'),
                    validator: _required,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Teléfono'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Correo de contacto'),
            ),
            const SizedBox(height: 24),
            Text('Tarifas', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _monthly,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Mensualidad'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _daily,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Pase diario'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Text('Registrar'),
            ),
          ],
        ),
      ),
    );
  }

  static String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Obligatorio' : null;
}
