// lib/modules/subscriptions/add/add_subscription_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../../core/constants/app_colors.dart';
import '../../../data/models/plan_model.dart';
import 'add_subscription_controller.dart';

class AddSubscriptionScreen extends GetView<AddSubscriptionController> {
  const AddSubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Get.back(),
        ),
        title: Obx(() => Text(
          controller.editingSub.value != null ? 'Edit Subscription' : 'New Subscription',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            fontFamily: 'Poppins',
          ),
        )),
      ),
      body: Form(
        key: controller.formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: Obx(() => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(
                step: '1',
                label: 'Who is this for?',
                icon: Icons.person_rounded,
              ),
              const SizedBox(height: 10),
              _CustomerPicker(controller: controller),
              const SizedBox(height: 20),
              const _Divider(),
              const SizedBox(height: 20),
              _SectionHeader(
                step: '2',
                label: 'Add Plan Templates',
                icon: Icons.assignment_outlined,
              ),
              const SizedBox(height: 10),
              _PlanBasketSection(controller: controller),
              const SizedBox(height: 20),
              const _Divider(),
              const SizedBox(height: 20),
              _SectionHeader(
                step: '3',
                label: 'Start Date',
                icon: Icons.calendar_today_rounded,
              ),
              const SizedBox(height: 10),
              _DatePickerButton(
                date: controller.startDate.value,
                onTap: controller.pickStartDate,
              ),
              const SizedBox(height: 20),
              const _Divider(),
              const SizedBox(height: 20),
              const _SectionHeader(
                step: '',
                label: 'Notes (optional)',
                icon: Icons.notes_rounded,
              ),
              const SizedBox(height: 10),
              _BigInputField(
                label: '',
                controller: controller.notesCtrl,
                maxLines: 3,
                hint: 'e.g. Leave at gate',
                prefix: null,
              ),
              const SizedBox(height: 28),
              _SaveButton(controller: controller),
            ],
          )),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String step;
  final String label;
  final IconData icon;
  const _SectionHeader({required this.step, required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      if (step.isNotEmpty) ...[
        Container(
          width: 28, height: 28,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
          child: Text(step, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white, fontFamily: 'Poppins')),
        ),
        const SizedBox(width: 10),
      ],
      Icon(icon, size: 20, color: AppColors.primary),
      const SizedBox(width: 8),
      Expanded(
        child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary, fontFamily: 'Poppins')),
      ),
    ]);
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => const Divider(color: AppColors.divider, thickness: 1, height: 1);
}

// ── Customer Picker ───────────────────────────────────────────────────────────

class _CustomerPicker extends StatelessWidget {
  final AddSubscriptionController controller;
  const _CustomerPicker({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final customers = controller.customers;
      if (customers.isEmpty) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.warning.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.warning.withOpacity(0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 20),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'No active customers found. Add a customer first.',
                style: TextStyle(fontSize: 13, color: AppColors.warning, fontFamily: 'Poppins'),
              ),
            ),
          ]),
        );
      }

      return AbsorbPointer(
        absorbing: controller.editingSub.value != null,
        child: Opacity(
          opacity: controller.editingSub.value != null ? 0.6 : 1.0,
          child: DropdownButtonFormField<String>(
            value: controller.selectedCustomer.value?.id,
            isExpanded: true,
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
              prefixIcon: const Icon(Icons.person_search_rounded, size: 22, color: AppColors.textHint),
              hintText: 'Choose customer',
            ),
            // Collapsed view: show name + phone
            selectedItemBuilder: (context) => customers.map((c) => Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(c.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontFamily: 'Poppins', fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                ],
              ),
            )).toList(),
            // Expanded dropdown: rich card with name, phone, address
            items: customers.map((c) => DropdownMenuItem(
              value: c.id,
              child: _CustomerDropdownItem(customer: c),
            )).toList(),
            onChanged: (id) => controller.selectedCustomer.value = controller.customers.firstWhereOrNull((c) => c.id == id),
            validator: (v) => v == null ? 'Please select a customer' : null,
          ),
        ),
      );
    });
  }
}

class _CustomerDropdownItem extends StatelessWidget {
  final dynamic customer; // CustomerModel
  const _CustomerDropdownItem({required this.customer});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40, height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.10),
              shape: BoxShape.circle,
            ),
            child: Text(
              customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primary, fontFamily: 'Poppins'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(customer.name,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary, fontFamily: 'Poppins'),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(children: [
                  const Icon(Icons.call_rounded, size: 12, color: AppColors.textHint),
                  const SizedBox(width: 4),
                  Text(customer.phone,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontFamily: 'Poppins'),
                  ),
                ]),
                if (customer.address.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.location_on_rounded, size: 12, color: AppColors.textHint),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        [customer.address, if (customer.landmark != null && customer.landmark!.isNotEmpty) customer.landmark!].join(', '),
                        style: const TextStyle(fontSize: 11, color: AppColors.textHint, fontFamily: 'Poppins'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Plan Basket ───────────────────────────────────────────────────────────────

class _PlanBasketSection extends StatelessWidget {
  final AddSubscriptionController controller;
  const _PlanBasketSection({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Obx(() {
                final plans = controller.activePlans;
                return DropdownButtonFormField<PlanModel>(
                  value: controller.selectedDropdownPlan.value,
                  isExpanded: true,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.surface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                    prefixIcon: const Icon(Icons.assignment_outlined, size: 20, color: AppColors.textHint),
                    hintText: 'Choose plan template',
                  ),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontFamily: 'Poppins'),
                  selectedItemBuilder: (context) => plans.map((p) => Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${p.name} · ₹${p.pricePerDelivery.toStringAsFixed(0)}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontFamily: 'Poppins', fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    ),
                  )).toList(),
                  items: plans.map((p) => DropdownMenuItem<PlanModel>(
                    value: p,
                    child: _PlanDropdownItem(plan: p, controller: controller),
                  )).toList(),
                  onChanged: (plan) => controller.selectedDropdownPlan.value = plan,
                );
              }),
            ),
            const SizedBox(width: 8),
            Obx(() {
              final selected = controller.selectedDropdownPlan.value;
              return SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: selected == null ? null : () => controller.addPlan(selected),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor: AppColors.primary.withOpacity(0.4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: Row(children: [
                    const Icon(Icons.add_rounded, color: Colors.white, size: 20),
                    const SizedBox(width: 4),
                    const Text('Add', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14, fontFamily: 'Poppins')),
                  ]),
                ),
              );
            }),
          ],
        ),
        const SizedBox(height: 12),
        Obx(() {
          final items = controller.selectedPlans;
          if (items.isEmpty) {
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant.withOpacity(0.5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border, width: 0.8),
              ),
              child: Column(children: [
                const Icon(Icons.shopping_basket_outlined, size: 28, color: AppColors.textHint),
                const SizedBox(height: 8),
                const Text('No plan templates added yet.', style: TextStyle(fontFamily: 'Poppins', fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                const Text('Choose a plan above and click "Add".', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textHint)),
              ]),
            );
          }
          return ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, index) {
              final item = items[index];
              return _BasketItemTile(item: item, controller: controller, onRemove: () => controller.removePlan(item.id));
            },
          );
        }),
        Obx(() {
          if (controller.selectedPlans.isEmpty) return const SizedBox.shrink();
          return Column(children: [
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.primary.withOpacity(0.2), width: 1),
              ),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Total Delivery Rate', style: TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  Text('₹${controller.totalDeliveryRate.toStringAsFixed(2)}', style: const TextStyle(fontFamily: 'Poppins', fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primary)),
                ]),
                const SizedBox(height: 4),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Estimated Monthly Revenue', style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: AppColors.textSecondary)),
                  Text('~₹${controller.estimatedMonthlyRevenue.toStringAsFixed(0)}/month', style: const TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
                ]),
              ]),
            ),
          ]);
        }),
      ],
    );
  }
}

// ── Plan Dropdown Item (open list) ────────────────────────────────────────────

class _PlanDropdownItem extends StatelessWidget {
  final PlanModel plan;
  final AddSubscriptionController controller;
  const _PlanDropdownItem({required this.plan, required this.controller});

  String get _serviceIcon {
    switch (plan.serviceType) {
      case 'milk':      return '🥛';
      case 'water':     return '💧';
      case 'newspaper': return '📰';
      case 'tiffin':    return '🍱';
      case 'grocery':   return '🛒';
      default:          return '📦';
    }
  }

  String get _frequencyLabel {
    switch (plan.frequencyStr) {
      case 'daily':        return 'Daily';
      case 'twice_daily':  return 'Twice Daily';
      case 'thrice_daily': return 'Thrice Daily';
      case 'alternate':    return 'Alternate Days';
      case 'weekdays':     return 'Weekdays';
      case 'weekends':     return 'Weekends';
      case 'weekly':       return 'Weekly';
      default:             return plan.frequencyStr;
    }
  }

  List<String> get _slotLabels {
    return plan.deliverySlotIds.map((id) {
      final slot = controller.timeSlots.firstWhereOrNull((s) => s.id == id);
      return slot?.label ?? id;
    }).toList();
  }

  List<String> get _areaNames {
    if (plan.deliveryAreaIds.isEmpty) return ['All Areas'];
    return plan.deliveryAreaIds.map((id) {
      final area = controller.deliveryAreas.firstWhereOrNull((a) => a.id == id);
      return area?.name ?? id;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final slots = _slotLabels;
    final areas = _areaNames;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon
          Container(
            width: 42, height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(_serviceIcon, style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name
                Text(plan.name,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary, fontFamily: 'Poppins'),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                // Qty · Frequency
                Text('${plan.quantity} ${plan.unit}  •  $_frequencyLabel',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontFamily: 'Poppins'),
                ),
                if (slots.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.access_time_rounded, size: 12, color: AppColors.textHint),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(slots.join(', '),
                        style: const TextStyle(fontSize: 11, color: AppColors.textHint, fontFamily: 'Poppins'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                ],
                if (areas.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.location_on_rounded, size: 12, color: AppColors.textHint),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(areas.join(', '),
                        style: const TextStyle(fontSize: 11, color: AppColors.textHint, fontFamily: 'Poppins'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                ],
                if (plan.description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(plan.description,
                    style: const TextStyle(fontSize: 11, color: AppColors.textHint, fontFamily: 'Poppins'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Price column
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('₹${plan.pricePerDelivery.toStringAsFixed(0)}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primary, fontFamily: 'Poppins'),
              ),
              Text('per delivery',
                style: const TextStyle(fontSize: 10, color: AppColors.textHint, fontFamily: 'Poppins'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Basket Item Tile (added plans list) ───────────────────────────────────────

class _BasketItemTile extends StatelessWidget {
  final SelectedPlanItem item;
  final AddSubscriptionController controller;
  final VoidCallback onRemove;
  const _BasketItemTile({required this.item, required this.controller, required this.onRemove});

  String get _serviceIcon {
    switch (item.plan.serviceType) {
      case 'milk':      return '🥛';
      case 'water':     return '💧';
      case 'newspaper': return '📰';
      case 'tiffin':    return '🍱';
      case 'grocery':   return '🛒';
      default:          return '📦';
    }
  }

  String get _frequencyLabel {
    switch (item.plan.frequencyStr) {
      case 'daily':        return 'Daily';
      case 'twice_daily':  return 'Twice Daily';
      case 'thrice_daily': return 'Thrice Daily';
      case 'alternate':    return 'Alternate Days';
      case 'weekdays':     return 'Weekdays';
      case 'weekends':     return 'Weekends';
      case 'weekly':       return 'Weekly';
      default:             return item.plan.frequencyStr;
    }
  }

  List<String> get _slotLabels {
    return item.plan.deliverySlotIds.map((id) {
      final slot = controller.timeSlots.firstWhereOrNull((s) => s.id == id);
      return slot?.label ?? id;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final plan = item.plan;
    final slots = _slotLabels;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Emoji icon
          Container(
            width: 40, height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(_serviceIcon, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(plan.name,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 2),
                Text('${plan.quantity} ${plan.unit}  •  $_frequencyLabel',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textSecondary),
                ),
                if (slots.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Row(children: [
                    const Icon(Icons.access_time_rounded, size: 11, color: AppColors.textHint),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(slots.join(', '),
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textHint),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                ],
                if (plan.deliveryAreaIds.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(children: [
                    const Icon(Icons.location_on_rounded, size: 11, color: AppColors.textHint),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        plan.deliveryAreaIds.map((id) {
                          final area = controller.deliveryAreas.firstWhereOrNull((a) => a.id == id);
                          return area?.name ?? id;
                        }).join(', '),
                        style: const TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textHint),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                ] else ...[
                  const SizedBox(height: 2),
                  const Row(children: [
                    Icon(Icons.location_on_rounded, size: 11, color: AppColors.textHint),
                    SizedBox(width: 4),
                    Text('All Areas', style: TextStyle(fontFamily: 'Poppins', fontSize: 11, color: AppColors.textHint)),
                  ]),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('₹${plan.pricePerDelivery.toStringAsFixed(0)}',
                style: const TextStyle(fontFamily: 'Poppins', fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 2),
              GestureDetector(
                onTap: onRemove,
                child: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Shared Widgets ─────────────────────────────────────────────────────────────

class _BigInputField extends StatelessWidget {
  final String label;
  final String? hint;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;
  final Widget? prefix;
  final int maxLines;

  const _BigInputField({required this.label, required this.controller, this.hint, this.keyboardType, this.inputFormatters, this.validator, this.prefix, this.maxLines = 1});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      maxLines: maxLines,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontFamily: 'Poppins'),
      decoration: InputDecoration(
        labelText: label.isEmpty ? null : label,
        hintText: hint,
        labelStyle: const TextStyle(fontSize: 13, color: AppColors.textSecondary, fontFamily: 'Poppins'),
        hintStyle: const TextStyle(fontSize: 14, color: AppColors.textHint, fontFamily: 'Poppins'),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        prefixIcon: prefix != null ? Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: prefix) : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.error, width: 1.5)),
      ),
    );
  }
}

class _DatePickerButton extends StatelessWidget {
  final DateTime date;
  final VoidCallback onTap;
  const _DatePickerButton({required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final formatted = '${date.day.toString().padLeft(2, '0')} / ${date.month.toString().padLeft(2, '0')} / ${date.year}';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
        child: Row(children: [
          const Icon(Icons.event_rounded, size: 22, color: AppColors.primary),
          const SizedBox(width: 12),
          Text(formatted, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontFamily: 'Poppins')),
          const Spacer(),
          const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textHint),
        ]),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  final AddSubscriptionController controller;
  const _SaveButton({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isEdit = controller.editingSub.value != null;
      return SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: controller.isLoading.value ? null : controller.save,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            disabledBackgroundColor: AppColors.primary.withOpacity(0.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 3,
            shadowColor: AppColors.primary.withOpacity(0.4),
          ),
          child: controller.isLoading.value
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(isEdit ? Icons.check_circle_outline_rounded : Icons.add_circle_outline_rounded, size: 22, color: Colors.white),
            const SizedBox(width: 10),
            Text(isEdit ? 'Update Subscription' : 'Add Subscription', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white, fontFamily: 'Poppins')),
          ]),
        ),
      );
    });
  }
}