# GarStreamRx hardware contract

`requirements.json` は GarStreamRx が必要とする装置・信号の宣言であり、特定ボードの
GPIO offset や接続先を含みません。`bindings/luckfox-rk3506.json` が、その要件を
Luckfox Lyra Plus の capability resource に接続します。`gar hw validate --json` は
この二つと Target capability を照合し、pin conflict、driver/voltage不足、SPI bus/CSの
重複および速度不足を配置前に報告します。

CSV は simulator 用の legacy device contract です。KY-040 は lines 20/21/22、ILI9341の
DC/RST は lines 23/24 のままです。これは実機 binding（DC/RST=3/2、A/B/SW=8/9/10）と
意図的に別で、実機の配線やmachine-local設定をartifactへ混ぜません。
