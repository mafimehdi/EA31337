# آزمون تک‌عاملی سخت‌گیری SP2L در MT5

**۴ فایل INI مستقل، بدون SET** با قالب ذخیره‌شدهٔ MT5 شما (`[Tester]` و ۵۳ ورودی `[TesterInputs]`). تمام حالت‌ها `SignalMode=1`، `ReversalPrimary=0`، `UseReversal=true`، `RiskUSD=10`، `MaxOpenTrades=3` و `TradesPerSignal=3` دارند. فقط یک مقدار ورودی در هر فایل نسبت به کنترل تغییر می‌کند:

| نام کامل فایل | تغییر نسبت به کنترل |
|---|---|
| `goldfusion_mt5_sp2l_control_body045.ini` | هیچ؛ `SP2L_MinBodyRatio=0.45` |
| `goldfusion_mt5_sp2l_minbodyratio_060.ini` | `SP2L_MinBodyRatio=0.60` |
| `goldfusion_mt5_sp2l_minspikeatr_15.ini` | `SP2L_MinSpikeATR=1.5` |
| `goldfusion_mt5_sp2l_strictbreak_true.ini` | `SP2L_StrictBreak=true` |

این تغییرات **فرضیهٔ سخت‌گیری ورودند**، نه تضمین سیگنال باکیفیت‌تر یا سوددهی. کنترل پیش‌تر در Alpari-MT5 `XAUUSD_i`، M15، ۲۰۲۶، real ticks، سپردهٔ ۵۰۰ دلار و اهرم واقعی 1:100 نتیجهٔ ‎$44.04−، PF0.85، افت نسبی Equity26.61% و ۵۲۲ معامله داشت. اگر تاریخچه، EX5 یا حساب تفاوت دارد کنترل را دوباره بگیرید. هر سه تست جدید باید با همان شرایط و همان EX5 اصلاح‌شدهٔ دارای `OrderCalcProfit` انجام شوند. شرط‌های دیگر را دستی عوض نکنید.

**اجرای INI:** این فایل‌ها پیکربندی کامل Strategy Tester هستند و برای `terminal64.exe /config:"مسیر-کامل\\goldfusion_mt5_sp2l_minbodyratio_060.ini"` طراحی شده‌اند؛ دکمهٔ Load در تب Inputs ممکن است این نوع INI را اعمال نکند. اگر از GUI استفاده می‌کنید، مقادیر هر حالت را مطابق جدول بالا دستی وارد کنید. قبل از مقایسه، در Journal و Results بررسی کنید `SignalMode=1`، `ReversalPrimary=0`، `UseReversal=true`، `leverage 1:100` و مقدار آزمایشی موردنظر **واقعاً اعمال شده‌اند**؛ اگر اهرم 1:1 شد نتیجه نامعتبر است. نام فایل EX5 در INI `15.ex5` است؛ اگر فایل شما نام دیگری دارد مقدار `Expert` را اصلاح کنید. حساب باید Hedging باشد.

برای هر حالت تصویر Results و خطوط `[EXIT_SUMMARY]` را بفرستید. معیار مقایسه فقط سود نیست؛ PF، افت سرمایه، تعداد معاملات و زیان SL اولیه را هم بررسی کنید. آزمون چند گزینه با همان دادهٔ ۲۰۲۶ خطر بیش‌برازش دارد؛ هیچ نتیجه‌ای به‌تنهایی مجوز اجرای واقعی نیست. این فایل‌ها در MT5 توسط سازنده اجرا نشده‌اند.
