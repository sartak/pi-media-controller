#!/usr/bin/env perl
use 5.14.0;
use warnings;
use lib 'lib';
use lib 'extlib';
use utf8::all;
use Getopt::Whatever;
use autodie ':all';

$ARGV{black} = 'AlphaGo' if $ARGV{alphago};
$ARGV{white} = 'AlphaGo' if $ARGV{alphago};

die "--id required" unless $ARGV{id};
die "--black required" unless $ARGV{black};
die "--white required" unless $ARGV{white};
die "--commenter required" unless $ARGV{commenter};
die "URL required" unless @ARGV == 1 || $ARGV{url} || $ARGV{'skip-download'};

my %ja_for;
my %en_for;
while (<DATA>) {
    chomp;
    next unless /\S/;
    my ($en, $ja) = split '/', $_;
    $ja_for{$en} = $ja;
    $en_for{$ja} = $en;
}

for my $color (qw/black white commenter/) {
    $ARGV{$color} = $en_for{$ARGV{$color}} || $ARGV{$color};
    for my $name (split /\s*&\s*/, $ARGV{$color}) {
        die "No translation for $color '$name'\n" unless $ja_for{$name};
    }
}

my $id        = $ARGV{id};
my $black     = $ARGV{black};
my $white     = $ARGV{white};
my $commenter = $ARGV{commenter};
my $url       = $ARGV{url} || shift;
my $segment   = $ARGV{master}  ? "Master Series"
              : $ARGV{alphago} ? "AlphaGo vs AlphaGo"
                               : "Games";


unless ($ARGV{'skip-download'}) {
    die "$id already exists\n"
        if -e "/media/paul/Go/$segment/$id.mp4";

    $url = "https://www.youtube.com/watch?v=$url"
        unless $url =~ m{^https?://};

    system qq{cd /media/paul/tmp; ~/youtube-dl --format=18 "$url" -o $id.mp4};

    system "mv", "/media/paul/tmp/$id.mp4" => "/media/paul/Go/$segment/";
}

my $j_white     = join 'と', map { $ja_for{$_} } split /\s*&\s*/, $white;
my $j_black     = join 'と', map { $ja_for{$_} } split /\s*&\s*/, $black;
my $j_commenter = join 'と', map { $ja_for{$_} } split /\s*&\s*/, $commenter;

system (
    "perl",
    "-Ilib",
    "-Iextlib",
    "add-video.pl",
    "--streamable",
    "--segments=Go",
    "--segments=$segment",
    "/media/paul/Go/$segment/$id.mp4",
    "--identifier=$id" . (($ARGV{master}||$ARGV{alphago}) ? (" (#".($ARGV{master}||$ARGV{alphago}).")") : ""),
    (($ARGV{master}||$ARGV{alphago}) ? () : ("--sort_order=$id")),
    "--label_en=$black vs $white; $commenter commentary",
    "--label_ja=$j_black 対 $j_white ・ $j_commenter 解説",
);

__END__
Anonymous/名前の不明
AlphaGo/AlphaGo
Korean/韓国人

Akiyama Jiro/秋山次郎
Anzai Nobuaki/安斎伸彰
Aragaki Shun/新垣朱武
Awaji Shuzo/淡路修三
Chang Li Yu/張豊猷
Chen Yaoye/陳耀華
Cho Chikun/趙治勲
Cho Riyu/張豊猷
Cho Sonjin/趙善津
Cho U/張栩
Fujisawa Rina/藤沢里菜
Fuji Shuya/藤井秀哉
Goto Shungo/後藤俊午
Hane Naoki/羽根直樹
Ha Yeong-il/河英一
Hikosaka Naoto/彦坂直人
Ichiriki Ryo/一力遼
Ida Atsushi/伊田篤史
Imamura Toshiya/今村俊也
Imamura Yoshiaki/今村善彰
Ishida Yoshio/石田芳夫
Ishii Kunio/石井邦生
Ishikura Noboru/石倉昇
Iyama Yuta/井山裕太
Kanazawa Makoto/金沢真
Kataoka Satoshi/片岡聡
Kato Atsushi/加藤充志
Ke Jie/柯潔
Kenmochi Juu/剱持丈
Kim Soo Joon/金秀俊
Kim Sujun/金秀俊
Kiyonari Tetsuya/清成哲也
Kobayashi Koichi/小林光一
Kobayashi Satoru/小林覚
Ko Iso/黄翊祖
Komatsu Hideki/小松英樹
Ko Mosei/黄孟正
Kono Rin/河野臨
Ko Reibun/孔令文
Kou Iso/黄翊祖
Kouno Takashi/河野貴至
Kubo Katsuaki/久保勝昭
Kudo Norio/工藤紀夫
Kurahashi Masayuki/倉橋正行
Kyo Kagen/許家元
Lee Changho/李昌鎬
Lee Sedol/李世ドル
Matsumoto Takehisa/松本武久
Michael Redmond/マイケル・レドモンド
Mimura Tomoyasu/三村智保
Mizokami Tomochika/溝上知親
Mochizuki Kenichi/望月研一
Motoki Katsuya/本木克弥
Mukai Chiaki/向井千
Murakawa Daisuke/村川大介
Muramatsu Hiroki/村松大樹
Nakane Naoyuki/中根直行
Nakano Hironari/中野寛也
Nakano Yasuhiro/中野泰宏
Nakaonoda Tomomi/中小野田智己
Oba Junya/大場惇也
O Keii/王景怡
Okuda Aya/奥田あや
O Meien/王銘エン
Park Junghwan/パクジョンファン
Rin Kaiho/林海峰
Rin Kanketsu/林漢傑
Rin Shien/林子淵
Ryu Shikun/柳時薫
Sakai Hideyuki/坂井秀至
Seto Taiki/瀬戸大樹
Shibano Toramaru/芝野虎丸
Shida Tatsuya/志田達哉
So Kofuku/宋光復
Sonoda Yuichi/苑田勇一
So Yokoku/蘇耀国
Suzuki Ayumu/鈴木歩
Takanashi Seiken/高梨聖健
Takao Shinji/高尾紳路
Takemiya Masaki/武宮正樹
Tanaka Nobuyuki/田中伸幸
Tang Weixing/唐韦星
Terayama Rei/寺山怜
Tsuruyama Atsushi/鶴山淳志
Uchida Shuhei/内田修平
Xie Yiming/謝依旻
Yamada Kimio/山田規三生
Yamada Noriyoshi/山田規喜
Yamada Takuji/山田拓自
Yamashiro Hiroshi/山城宏
Yamashita Keigo/山下敬吾
Yi Tong-hun/イ・ドンフン
Yoda Norimoto/依田紀基
Yokota Shigeaki/横田茂昭
Yoon Chunho/尹春浩
Yo Seiki/余正麒
Yoshida Mika/吉田美香
Yukawa Mitsuhisa/湯川光久
Yuki Satoshi/結城聡
Gu Li/古力
Mi Yuting/ビイク廷
Kikugawa Yuseki/菊川友碩
Honinbo Dosaku/本因坊道策
Yasui Chitetsu/安井算知
Wu Boyi/呉柏毅
Hirata Tomoya/平田智也
O Rissei/王立誠
Han Zenki/潘善琪

Kang Tong-yun/Kang Tong-yun
An Seong-chun/An Seong-chun
Jennie Shen/Jennie Shen
Xie Erhao/Xie Erhao
Meng Tailing/Meng Tailing
Lian Xiao/Lian Xiao
Shi Yue/Shi Yue
Ryan Li/Ryan Li
Stephanie Yin/Stephanie Yin
Kim Chi-seok/Kim Chi-seok
Park Yeonghun/Park Yeonghun
Jiang Weijie/Jiang Weijie
Li Qincheng/Li Qincheng
Gu Zihao/Gu Zihao
Tan Xiao/Tan Xiao
