# ThinkingCaps — Tasarım Dokümanı

Tarih: 2026-08-01

## Amaç

Terminalde `claude` (Claude Code) bir işi işlerken ("düşünürken"), MacBook'un dahili
CapsLock ışığı yanıp söner. İş bitince ışık normal durumuna döner (CapsLock tuşunun
gerçek açık/kapalı durumunu yansıtır). CapsLock tuşu bu sırada da normal işlevini
korur — fiziksel tuşa basınca büyük/küçük harf yazımı hiç etkilenmez.

Uygulama, macOS menü çubuğunda yaşayan hafif bir arka plan uygulaması
(**ThinkingCaps.app**) olarak paketlenir; DMG olarak dağıtılır ve GitHub'da
public (MIT lisanslı) bir repo olarak paylaşılır.

## Kapsam Dışı (Non-goals)

- Windows/Linux desteği yok.
- Claude Code dışındaki araçlar (Cursor, Copilot vb.) için entegrasyon yok — ilk sürüm.
- Kod imzalama / Apple notarization yok — ilk sürüm unsigned dağıtılır, README'de
  Gatekeeper uyarısını geçme talimatı olur.
- Harici (USB/Bluetooth) klavye desteği garanti edilmiyor — hedef dahili MacBook klavyesi.
- Otomatik GitHub Actions build/release pipeline yok — ilk sürüm DMG'si elle hazırlanıp yüklenir.

## Mimari

Üç parça:

1. **Claude Code Hook Entegrasyonu** — `~/.claude/settings.json` içine `UserPromptSubmit`
   ve `Stop` hook'ları eklenir. Bu satırları elle değil, uygulamanın kendisi
   menüdeki "Claude Code Entegrasyonu" açma/kapama seçeneğiyle ekler/kaldırır.
2. **ThinkingCaps.app** — Swift + AppKit ile yazılmış, `NSStatusItem` tabanlı menü
   çubuğu uygulaması. İçinde:
   - Yerel bir unix socket sunucusu (hook mesajlarını dinler)
   - CapsLock LED kontrol mantığı (IOKit HID)
   - Aktif "düşünme" oturumlarının sayacı (aşağıda "Veri Akışı")
   - Menü UI'ı (entegrasyon aç/kapa, başlangıçta başlat, hakkında, çıkış)
3. **Yerel Soket İletişimi** — Hook, Claude Code tarafından tetiklendiğinde kısa
   ömürlü bir shell komutu çalıştırır; bu komut `nc -U` ile unix socket'e
   `start <session_id>` ya da `stop <session_id>` mesajı yazar. Socket path:
   `~/Library/Application Support/ThinkingCaps/ctl.sock`. Uygulama çalışmıyorsa
   yazma işlemi sessizce başarısız olur (hook her koşulda `exit 0` döner, Claude
   Code'un akışını hiçbir zaman bozmaz).

## Veri Akışı

1. Kullanıcı terminalde `claude`'a bir istek gönderir.
2. Claude Code `UserPromptSubmit` hook'unu tetikler → hook, socket'e
   `start <session_id>` yazar.
3. ThinkingCaps, aktif oturumlar kümesine `session_id`'yi ekler. Küme boştan
   dolu hale geçtiyse LED yanıp sönme döngüsünü başlatır (~400-500ms aralıkla toggle).
4. Claude Code işi bitirip `Stop` hook'unu tetikler → hook, socket'e
   `stop <session_id>` yazar.
5. ThinkingCaps, `session_id`'yi kümeden çıkarır. Küme boşaldıysa yanıp sönmeyi
   durdurur ve LED'i CapsLock'un gerçek açık/kapalı durumuna göre bırakır.

Birden fazla terminal penceresi aynı anda `claude` çalıştırıyorsa, küme boşalana
kadar (yani hepsi bitene kadar) yanıp sönme devam eder.

## Hata Durumları ve Uç Durumlar

- **Yarıda kesilen oturum** (Ctrl+C, çökme, vb.): `Stop` hook'u hiç tetiklenmeyebilir.
  Her `session_id` bir zaman damgasıyla saklanır; 10 dakika içinde `stop` gelmezse
  oturum otomatik olarak kümeden düşürülür (sonsuza kadar yanıp sönme riski önlenir).
- **Uygulama kapalıyken hook mesajı**: `nc -U` bağlantı hatası alır, hook yine de
  `exit 0` ile döner — Claude Code'un çalışmasını hiçbir şekilde engellemez.
- **Mac uyku/uyanma**: Uygulama uyanınca aktif oturum kümesini ve LED durumunu
  sıfırdan değerlendirir (varsayım: uykuya geçişte zaten `Stop` tetiklenmiş olur;
  değilse 10 dakikalık zaman aşımı devreye girer).
- **Uygulama yeniden başlatılırsa**: Soket dosyası temizlenip yeniden oluşturulur;
  önceki oturum kümesi kaybolur (kabul edilebilir — kritik olmayan bir görsel özellik).

## Kurulum & Dağıtım

1. **0. Adım — Teknik doğrulama (spike):** Gerçek uygulamayı yazmadan önce, IOKit
   HID Manager ile dahili klavyenin CapsLock LED elementini bulup değerini
   doğrudan değiştiren minik bir komut satırı test programı yazılır. Bu, şunları
   doğrular:
   - LED görsel olarak yanıp sönüyor mu?
   - Bu işlem CapsLock'un gerçek büyük/küçük harf durumunu (modifier state)
     etkiliyor mu? (Etkilememesi gerekiyor.)
   - Herhangi bir özel izin (örn. Input Monitoring) gerekiyor mu?
   - **Başarısız olursa yedek plan:** LED yerine menü çubuğu ikonunun kendisi
     yanıp söner (aynı start/stop sinyaliyle).
2. Xcode projesi oluşturulur (Swift + AppKit, minimal menü çubuğu uygulaması).
3. `.app` derlenip basit bir "Applications'a sürükle" görünümlü **DMG** paketi
   hazırlanır (`hdiutil` ile, elle çalıştırılan bir script).
4. **GitHub'da public repo** açılır: README (kurulum adımları + Gatekeeper
   uyarısını geçme talimatı: sağ tık > Aç), MIT LICENSE.
5. Başlangıçta başlatma, macOS'un modern `ServiceManagement` (SMAppService) API'si
   ile, menüdeki bir toggle üzerinden yönetilir — ayrı bir LaunchAgent plist dosyası
   elle kurulmaz.

## Test Planı

Bu görsel/donanımsal bir özellik olduğu için otomatik test yerine elle doğrulama
yapılır:

- 0. Adım prototipiyle LED kontrolünün çalıştığı ve CapsLock işlevini bozmadığı
  doğrulanır.
- Uygulama çalışırken terminalde gerçek bir `claude` isteği gönderilip LED'in
  yanıp söndüğü, istek bitince durduğu gözlemlenir.
- Aynı anda 2 terminal penceresinde `claude` çalıştırılıp, biri bitse bile
  diğeri bitmeden LED'in yanıp sönmeye devam ettiği doğrulanır.
- Uygulama kapalıyken `claude` çalıştırılıp hiçbir hata/gecikme oluşmadığı
  doğrulanır.
- Menüden "Claude Code Entegrasyonu" kapatılıp `~/.claude/settings.json`
  içindeki hook satırlarının temiz şekilde kaldırıldığı doğrulanır.

## Açık Riskler

- **En büyük risk:** Apple'ın son yıllardaki dahili klavye/CapsLock LED yönetim
  değişiklikleri nedeniyle, kullanıcı alanından (user space) doğrudan LED kontrolü
  MacBook'ta güvenilir çalışmayabilir. Bu risk 0. Adım prototipiyle en başta
  test edilip, gerekirse menü çubuğu ikonu yanıp sönmesine geçilecek.
