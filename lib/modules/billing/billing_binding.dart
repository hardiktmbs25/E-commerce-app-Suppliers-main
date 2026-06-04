// lib/modules/billing/billing_binding.dart
import 'package:get/get.dart';
import '../../data/repositories/billing_repository.dart';
import '../../services/billing_service.dart';
import '../../services/pdf_service.dart';
import 'billing_controller.dart';

class BillingBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<BillingRepository>(() => BillingRepository(), fenix: true);
    if (!Get.isRegistered<BillingService>()) {
      Get.put<BillingService>(BillingService(), permanent: true);
    }
    Get.lazyPut<PdfService>(() => PdfService(), fenix: true);
    Get.lazyPut<BillingController>(() => BillingController(), fenix: true);
  }
}
