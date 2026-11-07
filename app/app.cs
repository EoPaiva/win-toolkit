using System;
using System.Collections;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Net.NetworkInformation;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

[assembly: AssemblyTitle("upaiva.dev")]
[assembly: AssemblyProduct("upaiva.dev")]
[assembly: AssemblyDescription("upaiva.dev")]
[assembly: AssemblyVersion("1.1.0.0")]

namespace Upaiva {

// O WPF nao tem espacamento entre letras, e a identidade do site depende dele: titulos justos e rotulos abertos.
public class TextoTrack : FrameworkElement {
    public static readonly DependencyProperty TextoProperty = Reg("Texto", typeof(string), "");
    public static readonly DependencyProperty TamanhoProperty = Reg("Tamanho", typeof(double), 13.0);
    public static readonly DependencyProperty TrackProperty = Reg("Track", typeof(double), 0.0);
    public static readonly DependencyProperty FamiliaProperty = Reg("Familia", typeof(FontFamily), new FontFamily("Segoe UI"));
    public static readonly DependencyProperty CorProperty = Reg("Cor", typeof(Brush), Brushes.White);
    public static readonly DependencyProperty CaixaProperty = Reg("Caixa", typeof(bool), false);
    static DependencyProperty Reg(string n, Type t, object v) { return DependencyProperty.Register(n, t, typeof(TextoTrack), new FrameworkPropertyMetadata(v, FrameworkPropertyMetadataOptions.AffectsMeasure | FrameworkPropertyMetadataOptions.AffectsRender)); }
    public string Texto { get { return (string)GetValue(TextoProperty); } set { SetValue(TextoProperty, value); } }
    public double Tamanho { get { return (double)GetValue(TamanhoProperty); } set { SetValue(TamanhoProperty, value); } }
    public double Track { get { return (double)GetValue(TrackProperty); } set { SetValue(TrackProperty, value); } }
    public FontFamily Familia { get { return (FontFamily)GetValue(FamiliaProperty); } set { SetValue(FamiliaProperty, value); } }
    public Brush Cor { get { return (Brush)GetValue(CorProperty); } set { SetValue(CorProperty, value); } }
    public bool Caixa { get { return (bool)GetValue(CaixaProperty); } set { SetValue(CaixaProperty, value); } }

    string Final() { var t = Texto ?? ""; return Caixa ? t.ToUpper(new CultureInfo("pt-BR")) : t; }
    FormattedText Letra(string c) {
        return new FormattedText(c, CultureInfo.CurrentCulture, FlowDirection.LeftToRight, new Typeface(Familia, FontStyles.Normal, FontWeights.Normal, FontStretches.Normal), Tamanho, Cor, 1.0);
    }
    protected override Size MeasureOverride(Size s) {
        double larg = 0, alt = Math.Ceiling(Tamanho * 1.12);
        foreach (var c in Final()) larg += Letra(c.ToString()).WidthIncludingTrailingWhitespace + Track;
        return new Size(Math.Ceiling(Math.Max(0, larg - Track)), alt);
    }
    protected override void OnRender(DrawingContext dc) {
        double x = 0;
        foreach (var c in Final()) {
            var f = Letra(c.ToString());
            dc.DrawText(f, new Point(x, 0));
            x += f.WidthIncludingTrailingWhitespace + Track;
        }
    }
}

// O planeta de particulas do site. A orbita interna mostra o progresso real quando algo esta rodando.
public class Planeta : FrameworkElement {
    struct P3 { public double X, Y, Z; }
    readonly List<P3> pontos = new List<P3>();
    readonly List<double[]> anel1 = new List<double[]>(), anel2 = new List<double[]>();
    readonly Brush[] brilho = new Brush[9];
    readonly Brush corpo, halo, cometa;
    readonly Pen contorno;
    double rot, fase;
    public double Progresso = -1;
    public bool Ativo;

    static Brush Branco(byte a) { var b = new SolidColorBrush(Color.FromArgb(a, 255, 255, 255)); b.Freeze(); return b; }
    public Planeta() {
        IsHitTestVisible = false;
        const int n = 760;
        double dourado = Math.PI * (3 - Math.Sqrt(5));
        for (int i = 0; i < n; i++) {
            double y = 1 - i / (double)(n - 1) * 2, r = Math.Sqrt(Math.Max(0, 1 - y * y)), t = dourado * i;
            pontos.Add(new P3 { X = Math.Cos(t) * r, Y = y, Z = Math.Sin(t) * r });
        }
        var a = new Random(11);
        for (int i = 0; i < 300; i++) anel1.Add(new[] { i / 300.0 * Math.PI * 2, 1 + (a.NextDouble() - 0.5) * 0.05 });
        for (int i = 0; i < 130; i++) anel2.Add(new[] { i / 130.0 * Math.PI * 2, 1 + (a.NextDouble() - 0.5) * 0.03 });
        for (int i = 0; i < 9; i++) brilho[i] = Branco((byte)(14 + i * 30));
        var c = new RadialGradientBrush { GradientOrigin = new Point(0.3, 0.26), Center = new Point(0.42, 0.4), RadiusX = 0.72, RadiusY = 0.72 };
        c.GradientStops.Add(new GradientStop(Color.FromRgb(38, 38, 38), 0)); c.GradientStops.Add(new GradientStop(Color.FromRgb(9, 9, 9), 0.72)); c.GradientStops.Add(new GradientStop(Color.FromRgb(2, 2, 2), 1)); c.Freeze(); corpo = c;
        var h = new RadialGradientBrush();
        h.GradientStops.Add(new GradientStop(Color.FromArgb(20, 255, 255, 255), 0)); h.GradientStops.Add(new GradientStop(Color.FromArgb(0, 255, 255, 255), 1)); h.Freeze(); halo = h;
        var cm = new RadialGradientBrush();
        cm.GradientStops.Add(new GradientStop(Color.FromArgb(70, 255, 255, 255), 0)); cm.GradientStops.Add(new GradientStop(Color.FromArgb(0, 255, 255, 255), 1)); cm.Freeze(); cometa = cm;
        contorno = new Pen(Branco(38), 0.8); contorno.Freeze();
    }
    public void Avancar() { rot += Ativo ? 0.011 : 0.0035; fase += Ativo ? 0.012 : 0.004; InvalidateVisual(); }

    protected override void OnRender(DrawingContext dc) {
        double w = ActualWidth, h = ActualHeight;
        if (w <= 0) return;
        double cx = w * 0.5, cy = h * 0.5, R = Math.Min(w, h) * 0.44;
        dc.DrawEllipse(halo, null, new Point(cx, cy), R * 2.3, R * 2.1);
        double lim = Progresso >= 0 ? Progresso : -1;
        Anel(dc, anel2, cx, cy, R * 2.05, R * 0.62, -0.17, -1, true, -1);
        Anel(dc, anel1, cx, cy, R * 1.52, R * 0.30, -0.1, lim, true, 0);
        dc.DrawEllipse(corpo, contorno, new Point(cx, cy), R, R);
        double cr = Math.Cos(rot), sr = Math.Sin(rot);
        double lx = -0.5, ly = -0.62, lz = 0.6;
        foreach (var p in pontos) {
            double x = p.X * cr - p.Z * sr, z = p.X * sr + p.Z * cr, y = p.Y * 0.97 + z * 0.24, zz = z * 0.97 - p.Y * 0.24;
            if (zz <= 0) continue;
            double luz = Math.Max(0, x * lx + y * ly + zz * lz);
            int b = Math.Min(8, (int)(luz * 9.5));
            if (b == 0) continue;
            double t = 1.05 + zz * 0.85;
            dc.DrawRectangle(brilho[b], null, new Rect(cx + x * R, cy + y * R, t, t));
        }
        Anel(dc, anel1, cx, cy, R * 1.52, R * 0.30, -0.1, lim, false, 0);
        Anel(dc, anel2, cx, cy, R * 2.05, R * 0.62, -0.17, -1, false, -1);
        Cometa(dc, cx, cy, R * 2.05, R * 0.62, -0.17, fase * 0.72);
        Cometa(dc, cx, cy, R * 2.05, R * 0.62, -0.17, fase * 0.72 + 3.6);
    }
    void Anel(DrawingContext dc, List<double[]> a, double cx, double cy, double rx, double ry, double inc, double lim, bool atras, int tipo) {
        double ci = Math.Cos(inc), si = Math.Sin(inc), giro = tipo == 0 ? 0 : fase * 0.4;
        foreach (var q in a) {
            double ang = q[0] + giro, sn = Math.Sin(ang);
            if ((sn < 0) != atras) continue;
            double px = Math.Cos(ang) * rx * q[1], py = sn * ry * q[1], x = cx + px * ci - py * si, y = cy + px * si + py * ci;
            int b = tipo == 0 ? 3 : 1; double t = tipo == 0 ? 1.3 : 1.1;
            if (lim >= 0) { bool aceso = q[0] / (Math.PI * 2) <= lim; b = aceso ? 8 : 1; if (aceso) t = 2; }
            dc.DrawRectangle(brilho[b], null, new Rect(x, y, t, t));
        }
    }
    void Cometa(DrawingContext dc, double cx, double cy, double rx, double ry, double inc, double ang) {
        double ci = Math.Cos(inc), si = Math.Sin(inc);
        for (int i = 0; i < 16; i++) {
            double a = ang - i * 0.018, px = Math.Cos(a) * rx, py = Math.Sin(a) * ry;
            double x = cx + px * ci - py * si, y = cy + px * si + py * ci, t = 2.2 - i * 0.1;
            dc.DrawRectangle(brilho[Math.Max(1, 8 - i / 2)], null, new Rect(x, y, t, t));
            if (i == 0) dc.DrawEllipse(cometa, null, new Point(x + 1, y + 1), 7, 7);
        }
    }
}

class Item { public string Rotulo, Id, Grupo; public List<string> Padroes = new List<string>(); public int Peso = 1; public CheckBox Caixa; public bool Catalogo; }
class Grupo { public string Nome; public List<Item> Itens = new List<Item>(); public CheckBox Caixa; public TextBlock Contador; public bool Catalogo; public FrameworkElement Bloco; }
class Linha { public TextBlock Etiqueta, Texto, Detalhe; public DateTime Inicio; }
class Marcavel { public string Id; public CheckBox Caixa; }

static class Nativo {
    [StructLayout(LayoutKind.Sequential)] public struct FT { public uint Low, High; public ulong V { get { return ((ulong)High << 32) | Low; } } }
    [DllImport("kernel32.dll")] public static extern bool GetSystemTimes(out FT idle, out FT kernel, out FT user);
    [StructLayout(LayoutKind.Sequential)] public class MEM { public uint dwLength = 64, dwMemoryLoad; public ulong total, avail, tp, ap, tv, av, ave; }
    [DllImport("kernel32.dll")] public static extern bool GlobalMemoryStatusEx([In, Out] MEM m);
}

class Aplicativo {
    Window w;
    string raiz, dados, logPath, relatorioPath, flagCancelar, arqFotoFim, abaAtual = "Instalar", abaDepois, tipoExec = "", nivelEscolhido = "media";
    string resto = "", alvoDigitado = "", situacao = "";
    List<Grupo> grupos = new List<Grupo>();
    Dictionary<string, string> rotulos = new Dictionary<string, string>();
    Dictionary<string, int> pesos = new Dictionary<string, int>();
    Dictionary<string, Linha> linhas = new Dictionary<string, Linha>();
    List<Marcavel> achados = new List<Marcavel>(), driversMarcaveis = new List<Marcavel>();
    List<Button> botoesFerramenta = new List<Button>();
    List<Action> acoesPaleta = new List<Action>();
    long posicaoLog;
    int total, concluidas, feitas, falhas, digitados, quadro;
    Process processo;
    DispatcherTimer relogio, animacao;
    bool emAndamento, atualizando, terminado, podeAlterar = true, semElevar, cancelando;
    // A aba MTA so mexe nas configuracoes do jogo: vale tambem no PC de origem das configs.
    bool podeAlterarMta = true, mtaAnalisado;
    List<Marcavel> correcoesMta = new List<Marcavel>();
    DateTime inicioExec;
    ulong antIdle, antTotal; long antRede, ultimoCpu; DateTime antRedeT = DateTime.Now;
    Planeta planeta;
    TextoTrack rotuloCatalogo;
    TextBlock semResultado;
    string tituloExec1 = "", tituloExec2 = "";
    bool simulando, fecharMesmoAssim;
    Action aoConfirmar;

    static readonly FontFamily Mono = new FontFamily("Cascadia Mono, Consolas");
    static readonly Brush Tinta = Cor("#FFFFFF"), Suave = Cor("#D4D4D4"), Mudo = Cor("#8C8C8C"), Fraco = Cor("#7A7A7A"), Sinal = Cor("#FF6B6B"), LinhaCor = Cor("#1C1C1C");
    static SolidColorBrush Cor(string h) { return (SolidColorBrush)new BrushConverter().ConvertFromString(h); }
    T C<T>(string nome) where T : class { return w.FindName(nome) as T; }
    FontFamily Fonte(string chave) { return (FontFamily)Application.Current.Resources[chave]; }

    [STAThread]
    static int Main(string[] args) {
        try { new Aplicativo().Rodar(args); return 0; }
        catch (Exception e) {
            // Nos testes nao ha quem feche a caixa de erro: ela prenderia o processo.
            string foto = Arg(args, "--foto") ?? Arg(args, "--foto-fim");
            if (foto != null) File.WriteAllText(foto + ".erro.txt", e.ToString());
            else MessageBox.Show(e.ToString(), "upaiva.dev", MessageBoxButton.OK, MessageBoxImage.Error);
            return 1;
        }
    }
    static string Arg(string[] a, string n) { int i = Array.IndexOf(a, n); return i >= 0 && i + 1 < a.Length ? a[i + 1] : null; }

    void Rodar(string[] args) {
        raiz = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\');
        if (Arg(args, "--raiz") != null) raiz = Arg(args, "--raiz");
        semElevar = args.Contains("--sem-elevar");
        dados = Environment.GetEnvironmentVariable("SETUP_DADOS");
        if (string.IsNullOrEmpty(dados)) dados = Path.Combine(Environment.GetEnvironmentVariable("USERPROFILE"), "SetupMateus");
        logPath = Path.Combine(dados, "logs", "instalador.log");
        relatorioPath = Path.Combine(dados, "relatorio.txt");
        flagCancelar = Path.Combine(dados, "cancelar.flag");

        var app = new Application();
        // A interface roda em outro processo que a instalacao: um erro de tela nao pode fechar a janela que a acompanha.
        app.DispatcherUnhandledException += (o, e) => { e.Handled = true; try { Term("ui.error " + e.Exception.Message); } catch { } };
        CarregarFontes(app);
        using (var s = Assembly.GetExecutingAssembly().GetManifestResourceStream("ui.xaml"))
        using (var r = new StreamReader(s, Encoding.UTF8)) w = (Window)XamlReader.Parse(r.ReadToEnd());
        planeta = C<Planeta>("Planeta");
        C<RichTextBox>("Terminal").Document = new FlowDocument { PagePadding = new Thickness(0), FontFamily = Mono, FontSize = 11.5 };

        CarregarLista();
        MontarGrupos();
        MontarPerfis();
        MontarNiveis();
        MontarFerramentas();
        MontarPaleta();

        C<Grid>("Topo").MouseLeftButtonDown += delegate { w.DragMove(); };
        C<Button>("Minimizar").Click += delegate { w.WindowState = WindowState.Minimized; };
        C<Button>("Fechar").Click += delegate { w.Close(); };
        C<Button>("Principal").Click += delegate { BotaoPrincipal(); };
        C<Button>("Cancelar").Click += delegate { PedirCancelamento(); };
        C<Button>("Relatorio").Click += delegate { if (File.Exists(relatorioPath)) Process.Start("notepad.exe", "\"" + relatorioPath + "\""); };
        C<Button>("Simular").Click += delegate { RodarOtimizar(true, false); };
        C<Button>("Reverter").Click += delegate { RodarOtimizar(false, true); };
        C<Button>("AnalisarDeNovo").Click += delegate { IniciarAnalise(); };
        C<Button>("BuscarDeNovo").Click += delegate { IniciarBuscaDrivers(); };
        C<Button>("AnalisarMta").Click += delegate { IniciarAnaliseMta(); };
        C<Button>("ReverterMta").Click += delegate { ReverterCorrecoesMta(); };
        C<Button>("ConfirmaNao").Click += delegate { C<Grid>("Confirma").Visibility = Visibility.Collapsed; };
        C<Button>("ConfirmaSim").Click += delegate { C<Grid>("Confirma").Visibility = Visibility.Collapsed; if (aoConfirmar != null) aoConfirmar(); };
        C<Button>("AbrirPaleta").Click += delegate { AbrirPaleta(); };
        C<Button>("FecharPaleta").Click += delegate { FecharPaleta(); };
        C<TextBox>("Busca").TextChanged += delegate { Filtrar(); };
        C<TextBox>("EntradaPaleta").TextChanged += delegate { AtualizarPaleta(); };
        C<TextBox>("EntradaPaleta").KeyDown += (o, e) => { if (e.Key == Key.Enter && acoesPaleta.Count > 0) { var a = acoesPaleta[0]; FecharPaleta(); a(); } };
        w.PreviewKeyDown += (o, e) => {
            if (C<Grid>("Confirma").Visibility == Visibility.Visible) { if (e.Key == Key.Escape) { C<Grid>("Confirma").Visibility = Visibility.Collapsed; e.Handled = true; } return; }
            if (e.Key == Key.K && Keyboard.Modifiers == ModifierKeys.Control) { AbrirPaleta(); e.Handled = true; }
            else if (e.Key == Key.Escape && C<Grid>("Paleta").Visibility == Visibility.Visible) { FecharPaleta(); e.Handled = true; }
        };
        foreach (var a in new[] { "Instalar", "Drivers", "Analisar", "Otimizar", "Ferramentas", "MTA", "Terminal" }) { var n = a; C<RadioButton>("Aba" + a).Checked += delegate { TrocarAba(n); }; }
        w.Closing += (o, e) => {
            if (!emAndamento || fecharMesmoAssim) return;
            e.Cancel = true;
            Confirmar("Fechar a janela?", "O que já começou continua rodando, mas você deixa de acompanhar por aqui.", "Fechar", delegate { fecharMesmoAssim = true; w.Close(); });
        };

        // Instalar ou otimizar aqui alteraria o PC de origem das configs. Analisar, simular e buscar so leem.
        if (string.Equals(Environment.GetEnvironmentVariable("COMPUTERNAME"), "MARINETE", StringComparison.OrdinalIgnoreCase)) { podeAlterar = false; Aviso("Somente leitura neste PC: é a origem das configs. Só Analisar, Simular, Buscar drivers e MTA funcionam."); }
        else if (new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator)) { podeAlterar = false; podeAlterarMta = false; Aviso("Abra com dois cliques, sem Executar como administrador. O Windows pede permissão na hora certa."); }
        if (semElevar && args.Contains("--permitir")) { podeAlterar = true; podeAlterarMta = true; C<TextBlock>("Aviso").Visibility = Visibility.Collapsed; }

        string foto = Arg(args, "--foto"), demo = Arg(args, "--demo"), aba = Arg(args, "--aba"), autoSim = Arg(args, "--auto-simular"), busca = Arg(args, "--busca");
        arqFotoFim = Arg(args, "--foto-fim");
        w.Loaded += delegate {
            IniciarAnimacoes();
            TrocarAba(abaAtual);
            if (aba != null) C<RadioButton>("Aba" + aba).IsChecked = true;
            if (busca != null) C<TextBox>("Busca").Text = busca;
            if (demo == "progresso") Demonstrar();
            if (args.Contains("--paleta")) AbrirPaleta();
            if (args.Contains("--confirmar")) RodarOtimizar(false, false);
            if (args.Contains("--auto")) w.Dispatcher.BeginInvoke(DispatcherPriority.Background, new Action(IniciarInstalacao));
            if (args.Contains("--auto-analisar")) w.Dispatcher.BeginInvoke(DispatcherPriority.Background, new Action(IniciarAnalise));
            if (args.Contains("--auto-drivers")) w.Dispatcher.BeginInvoke(DispatcherPriority.Background, new Action(IniciarBuscaDrivers));
            if (args.Contains("--auto-mta")) w.Dispatcher.BeginInvoke(DispatcherPriority.Background, new Action(IniciarAnaliseMta));
            if (autoSim != null) { nivelEscolhido = autoSim; w.Dispatcher.BeginInvoke(DispatcherPriority.Background, new Action(delegate { RodarOtimizar(true, false); })); }
            if (args.Contains("--auto-cancelar")) { var t0 = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(3000) }; t0.Tick += delegate { t0.Stop(); PedirCancelamento(); }; t0.Start(); }
            if (foto != null) { var t = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(2600) }; t.Tick += delegate { t.Stop(); Fotografar(foto); emAndamento = false; app.Shutdown(); }; t.Start(); }
        };
        app.Run(w);
    }

    void CarregarFontes(Application app) {
        string pasta = Path.Combine(raiz, "fonts");
        Func<string, string, string, FontFamily> f = (arq, fam, reserva) => File.Exists(Path.Combine(pasta, arq))
            ? new FontFamily(new Uri(new Uri(pasta + "\\"), "./"), "./" + arq + "#" + fam + ", " + reserva)
            : new FontFamily(reserva);
        app.Resources["FDisplay"] = f("InterDisplay-Light.ttf", "Inter Display Light", "Segoe UI Light");
        app.Resources["FThin"] = f("InterDisplay-Thin.ttf", "Inter Display Thin", "Segoe UI Light");
        app.Resources["FText"] = f("Inter-Regular.ttf", "Inter", "Segoe UI");
        app.Resources["FLabel"] = f("Inter-Medium.ttf", "Inter Medium", "Segoe UI Semibold");
    }

    void Confirmar(string titulo, string texto, string sim, Action ok) {
        C<TextoTrack>("ConfirmaTitulo").Texto = titulo;
        C<TextBlock>("ConfirmaTexto").Text = texto;
        C<Button>("ConfirmaSim").Content = sim;
        aoConfirmar = ok;
        C<Grid>("Confirma").Visibility = Visibility.Visible;
        // O foco comeca em Voltar: Enter sem querer nao aplica nada.
        C<Button>("ConfirmaNao").Focus();
    }

    void Aviso(string m) { var a = C<TextBlock>("Aviso"); a.Text = m; a.Visibility = Visibility.Visible; }
    void Fotografar(string arq) {
        var el = (FrameworkElement)w.Content;
        var bmp = new RenderTargetBitmap((int)el.ActualWidth, (int)el.ActualHeight, 96, 96, PixelFormats.Pbgra32);
        bmp.Render(el);
        var enc = new PngBitmapEncoder();
        enc.Frames.Add(BitmapFrame.Create(bmp));
        using (var f = File.Create(arq)) enc.Save(f);
    }

    // ---------- secoes ----------

    static readonly Dictionary<string, string[]> Secoes = new Dictionary<string, string[]> {
        { "Instalar", new[] { "01", "Programas e dependências", "Escolha o que entra.", "Tudo na versão mais nova." } },
        { "Drivers", new[] { "02", "Windows Update, fabricantes e componentes de jogos", "Drivers oficiais.", "Sem banco de terceiros." } },
        { "Analisar", new[] { "03", "Segurança e saúde do PC", "Análise do sistema.", "Só lê. Nada muda sem você marcar." } },
        { "Otimizar", new[] { "04", "Quatro níveis reversíveis", "Menos serviços e apps.", "Defender e Firewall ficam ligados." } },
        { "Ferramentas", new[] { "05", "Rotinas de manutenção", "Manutenção do Windows.", "Uma rotina por vez." } },
        { "MTA", new[] { "06", "Multi Theft Auto", "Anti-crash MTA.", "Sem mods nem promessa de FPS." } },
        { "Terminal", new[] { "07", "Saída real", "Nada em execução.", "Os comandos aparecem aqui." } },
    };

    void Titulo(string a, string b) { C<TextoTrack>("Titulo1").Texto = a; C<TextoTrack>("Titulo2").Texto = b; }
    // A saida continua chegando com outra aba aberta: o titulo dela nao pode ser trocado.
    void TituloExec(string a, string b) { tituloExec1 = a; tituloExec2 = b; if (abaAtual == "Terminal") Titulo(a, b); }

    void TrocarAba(string a) {
        abaAtual = a;
        var s = Secoes[a];
        C<TextoTrack>("NumeroSecao").Texto = s[0];
        C<TextoTrack>("RotuloSecao").Texto = s[1];
        if (a == "Terminal" && (emAndamento || terminado)) Titulo(tituloExec1, tituloExec2);
        else Titulo(s[2], s[3]);
        if (a != "Terminal" && !emAndamento) { planeta.Progresso = -1; C<Border>("BarraProgresso").Width = 0; }
        foreach (var v in new[] { "Instalar", "Drivers", "Analisar", "Otimizar", "Ferramentas", "MTA", "Terminal" }) ((FrameworkElement)w.FindName("Visao" + v)).Visibility = v == a ? Visibility.Visible : Visibility.Collapsed;
        var cont = C<Grid>("Conteudo");
        cont.BeginAnimation(UIElement.OpacityProperty, new DoubleAnimation(0.2, 1, new Duration(TimeSpan.FromMilliseconds(180))) { EasingFunction = new ExponentialEase { EasingMode = EasingMode.EaseOut } });
        AtualizarPainel();
    }

    void AtualizarPainel() {
        var b = C<Button>("Principal");
        b.Visibility = Visibility.Visible;
        b.Tag = null;
        if (emAndamento) { b.Content = "Em execução"; b.IsEnabled = false; C<CheckBox>("OpcaoParalelo").Visibility = Visibility.Collapsed; return; }
        C<CheckBox>("OpcaoParalelo").Visibility = Visibility.Collapsed;
        if (abaAtual == "Terminal") { if (terminado) { b.Content = "Voltar"; b.Tag = "sem"; b.IsEnabled = true; } else b.Visibility = Visibility.Collapsed; return; }
        bool instDrivers = podeAlterar && driversMarcaveis.Count > 0, corrigir = podeAlterar && achados.Count > 0;
        C<CheckBox>("OpcaoParalelo").Visibility = abaAtual == "Instalar" && podeAlterar ? Visibility.Visible : Visibility.Collapsed;
        C<Button>("BuscarDeNovo").Visibility = instDrivers ? Visibility.Visible : Visibility.Collapsed;
        C<Button>("AnalisarDeNovo").Visibility = corrigir ? Visibility.Visible : Visibility.Collapsed;
        if (abaAtual == "Instalar") { b.IsEnabled = podeAlterar; Recontar(); }
        else if (abaAtual == "Drivers") {
            int n = driversMarcaveis.Count(a => a.Caixa.IsChecked == true);
            b.Content = !instDrivers ? "Buscar drivers" : n == 0 ? "Marque um item" : "Instalar " + n + (n == 1 ? " item" : " itens");
            b.IsEnabled = !instDrivers || n > 0;
        }
        else if (abaAtual == "Analisar") {
            int n = achados.Count(a => a.Caixa.IsChecked == true);
            b.Content = !corrigir ? "Iniciar análise" : n == 0 ? "Marque um item" : "Corrigir " + n + (n == 1 ? " item" : " itens");
            b.IsEnabled = !corrigir || n > 0;
        }
        else if (abaAtual == "Otimizar") { b.Content = "Aplicar " + NomeNivel(nivelEscolhido); b.IsEnabled = podeAlterar; }
        else if (abaAtual == "MTA") {
            int n = correcoesMta.Count(a => a.Caixa.IsChecked == true);
            b.Content = !mtaAnalisado ? "Analisar MTA" : correcoesMta.Count == 0 ? "Nada a aplicar" : n == 0 ? "Marque um item" : "Aplicar " + n + (n == 1 ? " item" : " itens");
            b.IsEnabled = !mtaAnalisado || (n > 0 && podeAlterarMta);
            C<Button>("AnalisarMta").Visibility = mtaAnalisado ? Visibility.Visible : Visibility.Collapsed;
            C<Button>("ReverterMta").Visibility = BackupMtaExiste() ? Visibility.Visible : Visibility.Collapsed;
            C<Button>("ReverterMta").IsEnabled = podeAlterarMta;
        }
        else b.Visibility = Visibility.Collapsed;
    }

    static string NomeNivel(string n) { return n == "altissima" ? "Altíssima" : n == "media" ? "Média" : n == "alta" ? "Alta" : "Leve"; }

    void BotaoPrincipal() {
        if (emAndamento) return;
        if (abaAtual == "Terminal") {
            terminado = false;
            C<Button>("Relatorio").Visibility = Visibility.Collapsed;
            C<Border>("BarraProgresso").Width = 0;
            planeta.Progresso = -1;
            C<RadioButton>("Aba" + (abaDepois ?? "Instalar")).IsChecked = true;
            return;
        }
        if (abaAtual == "Instalar") IniciarInstalacao();
        else if (abaAtual == "Drivers") { if (podeAlterar && driversMarcaveis.Count > 0) InstalarDriversMarcados(); else IniciarBuscaDrivers(); }
        else if (abaAtual == "Analisar") { if (podeAlterar && achados.Count > 0) CorrigirMarcados(); else IniciarAnalise(); }
        else if (abaAtual == "Otimizar") RodarOtimizar(false, false);
        else if (abaAtual == "MTA") { if (mtaAnalisado && correcoesMta.Count > 0) AplicarCorrecoesMta(); else IniciarAnaliseMta(); }
    }

    // ---------- animacao e telemetria ----------

    void IniciarAnimacoes() {
        animacao = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(36) };
        animacao.Tick += delegate { Animar(); };
        animacao.Start();
        Telemetria();
    }

    void Animar() {
        if (w.WindowState == WindowState.Minimized) return;
        quadro++;
        if (SystemParameters.ClientAreaAnimation) planeta.Avancar(); else if (quadro == 1) planeta.InvalidateVisual();
        if (quadro % 2 == 0 && digitados < alvoDigitado.Length) { digitados++; }
        if (quadro % 28 == 0) Telemetria();
    }

    void Digitar(string t) { alvoDigitado = t; digitados = 0; }

    void Telemetria() {
        Nativo.FT i, k, u;
        if (Nativo.GetSystemTimes(out i, out k, out u)) {
            ulong tot = k.V + u.V;
            if (antTotal > 0 && tot > antTotal) ultimoCpu = Math.Max(0, 100 - (long)((i.V - antIdle) * 100 / (tot - antTotal)));
            antIdle = i.V; antTotal = tot;
        }
        var m = new Nativo.MEM();
        Nativo.GlobalMemoryStatusEx(m);
        long bytesRede = 0;
        try { foreach (var n in NetworkInterface.GetAllNetworkInterfaces()) if (n.OperationalStatus == OperationalStatus.Up && n.NetworkInterfaceType != NetworkInterfaceType.Loopback) bytesRede += n.GetIPv4Statistics().BytesReceived; } catch { }
        double seg = Math.Max(0.1, (DateTime.Now - antRedeT).TotalSeconds);
        double mbps = antRede > 0 ? Math.Max(0, (bytesRede - antRede) * 8 / 1000000.0 / seg) : 0;
        antRede = bytesRede; antRedeT = DateTime.Now;
        string extra = emAndamento && processo != null ? "    pid " + processo.Id + "    " + (DateTime.Now - inicioExec).ToString(@"hh\:mm\:ss") : "";
        C<TextBlock>("Telemetria").Text = "cpu " + ultimoCpu + "%    ram " + m.dwMemoryLoad + "%    net " + mbps.ToString("0.0") + " Mbps" + extra;
    }

    // ---------- instalar ----------

    Grupo ObterGrupo(string nome, bool catalogo) {
        var g = grupos.FirstOrDefault(x => x.Nome == nome);
        if (g == null) { g = new Grupo { Nome = nome, Catalogo = catalogo }; grupos.Add(g); }
        return g;
    }
    void Adicionar(string grupo, string rotulo, int peso, params string[] padroes) {
        var i = new Item { Rotulo = rotulo, Peso = peso, Grupo = grupo };
        i.Padroes.AddRange(padroes);
        ObterGrupo(grupo, false).Itens.Add(i);
    }
    static int Tam(Dictionary<string, object> d, string k) { return d.ContainsKey(k) ? ((ICollection)d[k]).Count : 0; }

    void CarregarLista() {
        foreach (var n in new[] { "Dependências (AIO)", "Navegador e utilitários", "Desenvolvimento", "Inteligência artificial", "Comunicação e mídia", "Jogos" }) ObterGrupo(n, false);
        var json = new JavaScriptSerializer { MaxJsonLength = int.MaxValue }.Deserialize<Dictionary<string, object>>(File.ReadAllText(Path.Combine(raiz, "programas.json"), Encoding.UTF8));
        var idsConhecidos = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var lista in new[] { "maquina", "usuario" }) {
            foreach (Dictionary<string, object> p in (ArrayList)json[lista]) {
                string id = (string)p["id"];
                string etapa = "Programa " + (p.ContainsKey("nome") ? (string)p["nome"] : id);
                string rot = p.ContainsKey("rotulo") ? (string)p["rotulo"] : id;
                rotulos[etapa] = rot;
                idsConhecidos.Add(id);
                // O peso aproxima a duracao: Build Tools nao vale o mesmo que 7-Zip na barra.
                int peso = p.ContainsKey("minutos") ? Math.Max(1, Convert.ToInt32(p["minutos"]) / 5) : 1;
                pesos[etapa] = peso;
                Adicionar(p.ContainsKey("grupo") ? (string)p["grupo"] : "Outros", rot, peso, etapa);
            }
        }
        string listaPc = Path.Combine(raiz, "programas-do-pc.txt");
        if (File.Exists(listaPc)) {
            var ja = new HashSet<string>(grupos.SelectMany(g => g.Itens).SelectMany(i => i.Padroes), StringComparer.OrdinalIgnoreCase);
            foreach (var l in File.ReadAllLines(listaPc).Select(x => x.Trim()).Where(x => x.Length > 0 && !x.StartsWith("#"))) {
                string e = "Programa " + l;
                if (ja.Add(e)) Adicionar("Encontrados no PC antes de formatar", l, 1, e);
            }
        }
        string listaLoja = Path.Combine(raiz, "loja-do-pc.txt");
        if (File.Exists(listaLoja)) {
            foreach (var l in File.ReadAllLines(listaLoja, Encoding.UTF8)) {
                var partes = l.Split(new[] { '#' }, 2);
                string id = partes[0].Trim();
                if (id.Length == 0 || idsConhecidos.Contains(id)) continue;
                string nome = partes.Length > 1 && partes[1].Trim().Length > 0 ? partes[1].Trim() : id;
                rotulos["Programa " + id] = nome;
                Adicionar("Encontrados no PC antes de formatar", nome, 1, "Programa " + id);
            }
        }
        Adicionar("Skills e configurações", "Skills e configs Claude e Codex", 8 + Tam(json, "marketplaces") + Tam(json, "plugins"), "Restaurar *", "Git com caminhos longos", "Marketplace *", "Plugin *", "Serena*", "Headroom", "Conferir hooks*");
        Adicionar("Skills e configurações", "npm, pip e Python via uv", Tam(json, "npm") + Tam(json, "pip") + Tam(json, "uv_python"), "npm *", "pip *", "Python * via uv");
        Adicionar("Skills e configurações", "Extensões do VS Code", Tam(json, "vscode"), "VS Code *");
        Adicionar("Sistema", "Driver de rede", 1, "Drivers de rede");
        string pastaWifi = Path.Combine(raiz, "wifi");
        if (Directory.Exists(pastaWifi) && Directory.GetFiles(pastaWifi, "*.xml").Length > 0) Adicionar("Sistema", "Redes Wi-Fi", 1, "Redes Wi-Fi");
        Adicionar("Sistema", ".NET Framework 3.5", 1, "NET Framework 3.5");
        Adicionar("Sistema", "Limpeza do Windows", 1, "Limpeza do Windows");
        if (json.ContainsKey("catalogo")) {
            foreach (Dictionary<string, object> g in (ArrayList)json["catalogo"]) {
                var gr = ObterGrupo((string)g["grupo"], true);
                foreach (ArrayList it in (ArrayList)g["itens"]) {
                    string id = (string)it[0], rot = (string)it[1];
                    rotulos["Programa " + id] = rot;
                    gr.Itens.Add(new Item { Rotulo = rot, Id = id, Catalogo = true, Grupo = gr.Nome });
                }
            }
        }
        grupos = grupos.Where(g => g.Itens.Count > 0).ToList();
    }

    void MontarGrupos() {
        var painel = C<StackPanel>("Grupos");
        semResultado = new TextBlock { Text = "Nenhum programa com esse nome.", FontFamily = Mono, Foreground = Mudo, FontSize = 12.5, Margin = new Thickness(0, 14, 0, 0), Visibility = Visibility.Collapsed };
        painel.Children.Add(semResultado);
        bool titulo = false;
        foreach (var g in grupos) {
            if (g.Catalogo && !titulo) {
                titulo = true;
                rotuloCatalogo = new TextoTrack { Texto = "Catálogo opcional", Caixa = true, Tamanho = 10.5, Track = 3, Familia = Fonte("FLabel"), Cor = Mudo, Margin = new Thickness(0, 26, 0, 10) };
                painel.Children.Add(rotuloCatalogo);
            }
            var bloco = new Border { BorderBrush = LinhaCor, BorderThickness = new Thickness(0, 1, 0, 0), Padding = new Thickness(0, 15, 0, 9) };
            var grid = new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(250) });
            grid.ColumnDefinitions.Add(new ColumnDefinition());
            var esq = new StackPanel();
            g.Caixa = new CheckBox { Content = new TextBlock { Text = g.Nome, FontSize = 13.5, TextWrapping = TextWrapping.Wrap, MaxWidth = 210, Foreground = Tinta }, IsChecked = !g.Catalogo, VerticalAlignment = VerticalAlignment.Top };
            g.Contador = new TextBlock { FontFamily = Mono, Foreground = Fraco, FontSize = 11, Margin = new Thickness(23, 4, 0, 0) };
            esq.Children.Add(g.Caixa); esq.Children.Add(g.Contador);
            grid.Children.Add(esq);
            var itens = new WrapPanel();
            Grid.SetColumn(itens, 1);
            foreach (var i in g.Itens) {
                i.Caixa = new CheckBox { Content = i.Rotulo, IsChecked = !i.Catalogo, Width = 212, Margin = new Thickness(0, 0, 0, 8) };
                i.Caixa.Checked += delegate { Recontar(); };
                i.Caixa.Unchecked += delegate { Recontar(); };
                itens.Children.Add(i.Caixa);
            }
            grid.Children.Add(itens);
            var gg = g;
            g.Caixa.Click += delegate { atualizando = true; foreach (var i in gg.Itens) i.Caixa.IsChecked = gg.Caixa.IsChecked == true; atualizando = false; Recontar(); };
            bloco.Child = grid;
            g.Bloco = bloco;
            painel.Children.Add(bloco);
        }
        Recontar();
    }

    void Recontar() {
        if (atualizando) return;
        int n = 0;
        foreach (var g in grupos) {
            int m = g.Itens.Count(i => i.Caixa != null && i.Caixa.IsChecked == true);
            if (g.Contador != null) g.Contador.Text = m + " de " + g.Itens.Count;
            if (g.Caixa != null) g.Caixa.IsChecked = m == g.Itens.Count;
            n += m;
        }
        if (abaAtual == "Instalar" && !emAndamento) {
            var b = C<Button>("Principal");
            b.Content = n == 0 ? "Nada selecionado" : "Instalar " + n + (n == 1 ? " item" : " itens");
            b.IsEnabled = podeAlterar && n > 0;
        }
    }

    void Filtrar() {
        string q = C<TextBox>("Busca").Text.Trim().ToLower();
        C<TextBlock>("DicaBusca").Visibility = q.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        foreach (var g in grupos) {
            int vis = 0;
            foreach (var i in g.Itens) {
                bool ok = q.Length == 0 || i.Rotulo.ToLower().Contains(q) || g.Nome.ToLower().Contains(q);
                i.Caixa.Visibility = ok ? Visibility.Visible : Visibility.Collapsed;
                if (ok) vis++;
            }
            g.Bloco.Visibility = vis > 0 ? Visibility.Visible : Visibility.Collapsed;
        }
        if (rotuloCatalogo != null) rotuloCatalogo.Visibility = grupos.Any(g => g.Catalogo && g.Bloco.Visibility == Visibility.Visible) ? Visibility.Visible : Visibility.Collapsed;
        semResultado.Visibility = grupos.Any(g => g.Bloco.Visibility == Visibility.Visible) ? Visibility.Collapsed : Visibility.Visible;
    }

    static readonly Dictionary<string, string[]> PerfisInstalar = new Dictionary<string, string[]> {
        { "Básico", new[] { "Dependências (AIO)", "Navegador e utilitários", "Comunicação e mídia", "Sistema" } },
        { "Gamer", new[] { "Dependências (AIO)", "Navegador e utilitários", "Comunicação e mídia", "Jogos", "Mais jogos", "Sistema" } },
        { "Dev", new[] { "Dependências (AIO)", "Navegador e utilitários", "Desenvolvimento", "Inteligência artificial", "Skills e configurações", "Desenvolvimento e DevOps", "Sistema" } },
        { "IA", new[] { "Dependências (AIO)", "Navegador e utilitários", "Desenvolvimento", "Inteligência artificial", "Skills e configurações", "IA: assistentes e modelos locais", "IA: editores e agentes de código", "IA: imagem, áudio e vídeo", "Sistema" } },
    };

    void AplicarPerfil(string nome) {
        atualizando = true;
        foreach (var g in grupos) foreach (var i in g.Itens) {
            if (nome == "Limpar") i.Caixa.IsChecked = false;
            else if (nome == "Completo") i.Caixa.IsChecked = !i.Catalogo;
            else i.Caixa.IsChecked = PerfisInstalar[nome].Contains(g.Nome);
        }
        atualizando = false;
        Recontar();
    }

    string ArqSelecao { get { return Path.Combine(dados, "selecao.txt"); } }
    void SalvarSelecao() {
        Directory.CreateDirectory(dados);
        File.WriteAllLines(ArqSelecao, grupos.SelectMany(g => g.Itens).Where(i => i.Caixa.IsChecked == true).Select(i => i.Grupo + "|" + i.Rotulo), new UTF8Encoding(false));
        C<TextBlock>("DicaBusca").Text = "seleção salva";
    }
    void CarregarSelecao() {
        if (!File.Exists(ArqSelecao)) { C<TextBlock>("DicaBusca").Text = "nenhuma seleção salva"; return; }
        var s = new HashSet<string>(File.ReadAllLines(ArqSelecao, Encoding.UTF8));
        atualizando = true;
        foreach (var g in grupos) foreach (var i in g.Itens) i.Caixa.IsChecked = s.Contains(i.Grupo + "|" + i.Rotulo);
        atualizando = false;
        Recontar();
    }

    void MontarPerfis() {
        var p = C<StackPanel>("Perfis");
        foreach (var n in new[] { "Completo", "Básico", "Gamer", "Dev", "IA", "Limpar" }) {
            var nome = n;
            var b = new Button { Style = (Style)w.FindResource("BotaoPilula"), Content = n, Margin = new Thickness(6, 0, 0, 0) };
            b.Click += delegate { AplicarPerfil(nome); };
            p.Children.Add(b);
        }
        var sv = new Button { Style = (Style)w.FindResource("BotaoPilula"), Content = "Salvar", Margin = new Thickness(18, 0, 0, 0) };
        sv.Click += delegate { SalvarSelecao(); };
        p.Children.Add(sv);
        var cg = new Button { Style = (Style)w.FindResource("BotaoPilula"), Content = "Carregar", Margin = new Thickness(6, 0, 0, 0) };
        cg.Click += delegate { CarregarSelecao(); };
        p.Children.Add(cg);
    }

    void IniciarInstalacao() {
        if (emAndamento || (!podeAlterar && !semElevar)) return;
        Directory.CreateDirectory(Path.GetDirectoryName(logPath));
        var todos = grupos.SelectMany(g => g.Itens).ToList();
        File.WriteAllLines(Path.Combine(dados, "pular.txt"), todos.Where(i => !i.Catalogo && i.Caixa.IsChecked != true).SelectMany(i => i.Padroes), new UTF8Encoding(false));
        File.WriteAllLines(Path.Combine(dados, "catalogo.txt"), todos.Where(i => i.Catalogo && i.Caixa.IsChecked == true).Select(i => i.Id), new UTF8Encoding(false));
        string arqParalelo = Path.Combine(dados, "paralelo.txt");
        if (C<CheckBox>("OpcaoParalelo").IsChecked == true) File.WriteAllText(arqParalelo, "1"); else if (File.Exists(arqParalelo)) File.Delete(arqParalelo);
        total = todos.Where(i => i.Caixa.IsChecked == true).Sum(i => i.Peso);
        abaDepois = "Instalar"; tipoExec = "instalar";
        Executar("instalar.ps1", "", false, "Instalando.");
        // Fila visivel desde o inicio: o que falta aparece antes de comecar.
        foreach (var i in todos.Where(x => x.Caixa.IsChecked == true)) {
            foreach (var pd in i.Padroes.Where(x => !x.Contains("*"))) { if (pd.StartsWith("Programa ") || pd.StartsWith("Drivers") || pd.StartsWith("Redes") || pd.StartsWith("NET") || pd.StartsWith("Limpeza")) Marcar(pd, "..", Fraco, ""); }
            if (i.Catalogo) Marcar("Programa " + i.Id, "..", Fraco, "");
        }
    }

    // ---------- drivers ----------

    void IniciarBuscaDrivers() {
        if (emAndamento) return;
        abaDepois = "Drivers"; tipoExec = "drivers"; total = 5;
        Executar("drivers.ps1", "-Acao buscar", false, "Buscando drivers.");
    }

    TextoTrack Secao(string t) { return new TextoTrack { Texto = t, Caixa = true, Tamanho = 10.5, Track = 3, Familia = Fonte("FLabel"), Cor = Mudo, Margin = new Thickness(0, 18, 0, 9) }; }
    Border Fila(UIElement filho) { return new Border { BorderBrush = LinhaCor, BorderThickness = new Thickness(0, 1, 0, 0), Padding = new Thickness(0, 12, 0, 12), Child = filho }; }
    TextBlock Dado(string t) { return new TextBlock { Text = t, FontFamily = Mono, Foreground = Mudo, FontSize = 11.5, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 3, 0, 0) }; }

    void CarregarDrivers() {
        var p = C<StackPanel>("ListaDrivers");
        p.Children.Clear(); driversMarcaveis.Clear();
        string arq = Path.Combine(dados, "drivers.json");
        if (!File.Exists(arq)) { C<TextBlock>("ResumoDrivers").Text = "drivers.json não foi gerado."; return; }
        var j = new JavaScriptSerializer { MaxJsonLength = int.MaxValue }.Deserialize<Dictionary<string, object>>(File.ReadAllText(arq, Encoding.UTF8));
        var ups = (ArrayList)j["atualizacoes"]; var prob = (ArrayList)j["problemas"];
        int antigos = Convert.ToInt32(j["antigos"]);
        string erro = j.ContainsKey("erro") ? (string)j["erro"] : "";
        var comps = (ArrayList)j["componentes"];
        string erroComp = (string)j["erroComponentes"];
        C<TextBlock>("ResumoDrivers").Text = ups.Count + " atualizações   " + comps.Count + " componentes de jogos   " + prob.Count + " dispositivos com erro   " + antigos + " drivers com mais de 3 anos";
        if (erro.Length > 0) p.Children.Add(Fila(new TextBlock { Text = "A busca no Windows Update falhou: " + erro, Foreground = Sinal, FontSize = 13, TextWrapping = TextWrapping.Wrap }));
        if (prob.Count > 0) {
            p.Children.Add(Secao("Dispositivos com erro"));
            foreach (Dictionary<string, object> d in prob) p.Children.Add(Fila(new TextBlock { Text = (string)d["nome"] + ", código " + (string)d["codigo"], Foreground = Sinal, FontSize = 13, TextWrapping = TextWrapping.Wrap }));
        }
        p.Children.Add(Secao("Windows Update"));
        if (ups.Count == 0 && erro.Length == 0) p.Children.Add(Fila(new TextBlock { Text = "Nenhuma atualização de driver no catálogo agora.", Foreground = Mudo, FontSize = 13 }));
        foreach (Dictionary<string, object> u in ups) {
            var txt = new StackPanel();
            txt.Children.Add(new TextBlock { Text = (string)u["titulo"], FontSize = 13, Foreground = Tinta, TextTrimming = TextTrimming.CharacterEllipsis, MaxWidth = 900 });
            txt.Children.Add(Dado((string)u["classe"] + "   " + (string)u["data"] + "   " + Convert.ToString(u["mb"]) + " MB"));
            var cx = new CheckBox { IsChecked = true, Content = txt };
            cx.Click += delegate { AtualizarPainel(); };
            driversMarcaveis.Add(new Marcavel { Id = (string)u["id"], Caixa = cx });
            p.Children.Add(Fila(cx));
        }
        p.Children.Add(Secao("Componentes de jogos"));
        if (erroComp.Length > 0) p.Children.Add(Fila(new TextBlock { Text = "A busca de componentes falhou: " + erroComp, Foreground = Sinal, FontSize = 13, TextWrapping = TextWrapping.Wrap }));
        else if (comps.Count == 0) p.Children.Add(Fila(new TextBlock { Text = "Todos instalados e atualizados.", Foreground = Mudo, FontSize = 13 }));
        foreach (Dictionary<string, object> c in comps) {
            var txt = new StackPanel();
            txt.Children.Add(new TextBlock { Text = (string)c["rotulo"], FontSize = 13, Foreground = Tinta });
            txt.Children.Add(Dado((string)c["estado"] == "atualizar" ? "versão nova disponível" : "não instalado"));
            var cx = new CheckBox { IsChecked = true, Content = txt };
            cx.Click += delegate { AtualizarPainel(); };
            driversMarcaveis.Add(new Marcavel { Id = (string)c["pedido"], Caixa = cx });
            p.Children.Add(Fila(cx));
        }
        var ferr = (ArrayList)j["ferramentas"];
        if (ferr.Count > 0) p.Children.Add(Secao("Ferramenta do fabricante"));
        foreach (Dictionary<string, object> f in ferr) {
            var cx = new CheckBox { IsChecked = false, Content = (string)f["rotulo"] };
            cx.Click += delegate { AtualizarPainel(); };
            driversMarcaveis.Add(new Marcavel { Id = "winget:" + (string)f["id"], Caixa = cx });
            p.Children.Add(Fila(cx));
        }
        var pag = (ArrayList)j["paginas"]; var gpu = (ArrayList)j["gpu"];
        if (gpu.Count > 0 || pag.Count > 0) p.Children.Add(Secao("Placa de vídeo"));
        foreach (Dictionary<string, object> g in gpu) {
            var st = new StackPanel();
            st.Children.Add(new TextBlock { Text = (string)g["nome"], FontSize = 13, Foreground = Tinta });
            st.Children.Add(Dado("driver " + (string)g["versao"] + "   " + (string)g["data"]));
            p.Children.Add(Fila(st));
        }
        foreach (Dictionary<string, object> s in pag) {
            string url = (string)s["url"];
            var b = new Button { Style = (Style)w.FindResource("BotaoPilula"), Content = "Abrir site" };
            b.Click += delegate { Process.Start(url); };
            var d = new DockPanel();
            DockPanel.SetDock(b, Dock.Right);
            d.Children.Add(b);
            d.Children.Add(new TextBlock { Text = (string)s["rotulo"] + ", a versão mais nova direto do fabricante", Foreground = Suave, FontSize = 13, VerticalAlignment = VerticalAlignment.Center });
            p.Children.Add(Fila(d));
        }
    }

    void InstalarDriversMarcados() {
        var ids = driversMarcaveis.Where(a => a.Caixa.IsChecked == true).Select(a => a.Id).ToList();
        if (ids.Count == 0 || emAndamento || !podeAlterar) return;
        Confirmar("Instalar " + ids.Count + (ids.Count == 1 ? " item?" : " itens?"), "Um ponto de restauração é criado antes. Pode ser preciso reiniciar.", "Instalar", delegate {
            // A lista deixa de valer depois de instalar: a proxima acao e buscar de novo.
            C<StackPanel>("ListaDrivers").Children.Clear(); driversMarcaveis.Clear();
            C<TextBlock>("ResumoDrivers").Text = "Busque de novo para conferir o resultado.";
            abaDepois = "Drivers"; tipoExec = "ferramenta"; total = ids.Count + 1;
            Executar("drivers.ps1", "-Acao instalar -Ids " + string.Join(",", ids), true, "Instalando drivers.");
        });
    }

    // ---------- analisar ----------

    void IniciarAnalise() {
        if (emAndamento) return;
        abaDepois = "Analisar"; tipoExec = "analisar"; total = 26;
        Executar("analisar.ps1", C<CheckBox>("Profundo").IsChecked == true ? "-Profundo" : "", !semElevar, "Analisando este PC.");
    }

    void CarregarAchados() {
        var painel = C<StackPanel>("Achados");
        painel.Children.Clear(); achados.Clear();
        string arq = Path.Combine(dados, "analise.json");
        if (!File.Exists(arq)) { C<TextBlock>("ResumoAnalise").Text = "analise.json não foi gerado."; return; }
        var lista = new JavaScriptSerializer { MaxJsonLength = int.MaxValue }.Deserialize<ArrayList>(File.ReadAllText(arq, Encoding.UTF8));
        int crit = 0, alto = 0, med = 0, ok = 0, naoLidos = 0;
        foreach (Dictionary<string, object> a in lista) {
            string sev = (string)a["sev"], id = (string)a["id"];
            if (sev == "CRITICO") crit++; else if (sev == "ALTO") alto++; else if (sev == "MEDIO") med++; else if (sev == "OK") ok++;
            bool naoLido = id.StartsWith("erro-");
            if (naoLido) naoLidos++;
            Brush cor = sev == "CRITICO" || sev == "ALTO" ? Sinal : sev == "MEDIO" ? Tinta : Mudo;
            var linha = new DockPanel();
            var et = new TextoTrack { Texto = naoLido ? "Não lido" : sev == "CRITICO" ? "Crítico" : sev == "ALTO" ? "Alto" : sev == "MEDIO" ? "Médio" : sev == "INFO" ? "Info" : "OK", Caixa = true, Tamanho = 10, Track = 2, Familia = Fonte("FLabel"), Cor = cor, Width = 86, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 3, 0, 0) };
            DockPanel.SetDock(et, Dock.Left);
            linha.Children.Add(et);
            if (a.ContainsKey("fix") && (bool)a["fix"] && podeAlterar) {
                var cx = new CheckBox { Content = "corrigir", IsChecked = false, VerticalAlignment = VerticalAlignment.Top };
                cx.Click += delegate { AtualizarPainel(); };
                DockPanel.SetDock(cx, Dock.Right);
                linha.Children.Add(cx);
                achados.Add(new Marcavel { Id = id, Caixa = cx });
            }
            var txt = new StackPanel();
            txt.Children.Add(new TextBlock { Text = (string)a["titulo"], Foreground = sev == "OK" ? Mudo : Tinta, FontSize = 13, TextWrapping = TextWrapping.Wrap });
            txt.Children.Add(Dado((string)a["det"]));
            linha.Children.Add(txt);
            painel.Children.Add(Fila(linha));
        }
        C<TextBlock>("ResumoAnalise").Text = crit + " críticos   " + alto + " altos   " + med + " médios   " + ok + " ok" + (naoLidos > 0 ? "   " + naoLidos + (naoLidos == 1 ? " não lido" : " não lidos") : "");
    }

    void CorrigirMarcados() {
        var ids = achados.Where(a => a.Caixa.IsChecked == true).Select(a => a.Id).ToList();
        if (ids.Count == 0 || emAndamento || !podeAlterar) return;
        C<StackPanel>("Achados").Children.Clear(); achados.Clear();
        C<TextBlock>("ResumoAnalise").Text = "Analise de novo para conferir o resultado.";
        abaDepois = "Analisar"; tipoExec = "ferramenta"; total = ids.Count;
        Executar("ferramentas.ps1", "-Acao corrigir -Ids " + string.Join(",", ids), true, "Corrigindo.");
    }

    // ---------- otimizar ----------

    void MontarNiveis() {
        var p = C<System.Windows.Controls.Primitives.UniformGrid>("Niveis");
        Nivel(p, "leve", "01", "Leve", "Sem perda de função", "Tira anúncios, sugestões e apps instalados sozinhos. Telemetria no mínimo, sem P2P no Windows Update, Modo de Jogo e Storage Sense ligados.", false);
        Nivel(p, "media", "02", "Média", "Risco baixo", "Remove 21 apps, como Copilot, Widgets e Teams. Desliga Recall e DiagTrack. Liga HAGS e o plano Alto Desempenho, que gasta mais bateria.", true);
        Nivel(p, "alta", "03", "Alta", "Perde impressora e busca indexada", "Desliga SysMain, Windows Search, Xbox Live, Spooler e relatório de erros. Remove Game Bar. Sem hibernação e transparência, com Ultimate Performance.", false);
        Nivel(p, "altissima", "04", "Altíssima", "Perde localização, sensores, smart card e Miracast", "Fica só o que rede, áudio, login, loja, segurança e jogos usam: quase 90 serviços a mais desligados, sem apps em segundo plano, Power Throttling ou Inicialização Rápida. Para PC na tomada.", false);
    }

    void Nivel(System.Windows.Controls.Primitives.UniformGrid p, string id, string num, string nome, string risco, string texto, bool marcado) {
        var st = new StackPanel();
        st.Children.Add(new TextBlock { Text = num, FontFamily = Mono, Foreground = Fraco, FontSize = 11, Margin = new Thickness(0, 0, 0, 8) });
        var rotulo = new TextoTrack { Texto = nome, Tamanho = 32, Track = -1, Familia = Fonte("FDisplay"), Cor = marcado ? Tinta : Mudo, Margin = new Thickness(0, 0, 0, 8) };
        st.Children.Add(rotulo);
        st.Children.Add(new TextBlock { Text = risco, Foreground = Suave, FontSize = 13, Margin = new Thickness(0, 0, 0, 12), TextWrapping = TextWrapping.Wrap });
        st.Children.Add(new TextBlock { Text = texto, Foreground = Mudo, FontSize = 13.5, TextWrapping = TextWrapping.Wrap, LineHeight = 22 });
        var b = new RadioButton { Style = (Style)w.FindResource("Nivel"), GroupName = "Niveis", Content = st, IsChecked = marcado };
        var i = id;
        b.Checked += delegate { nivelEscolhido = i; rotulo.Cor = Tinta; AtualizarPainel(); };
        b.Unchecked += delegate { rotulo.Cor = Mudo; };
        p.Children.Add(b);
    }

    void RodarOtimizar(bool simular, bool reverter) {
        if (emAndamento || (!simular && !podeAlterar)) return;
        string a = reverter ? "-Reverter" : "-Nivel " + nivelEscolhido + (simular ? " -Simular" : "");
        if (C<CheckBox>("OpcaoVBS").IsChecked == true && !reverter) a += " -DesligarVBS";
        string nome = NomeNivel(nivelEscolhido);
        Action rodar = delegate {
            abaDepois = "Otimizar"; tipoExec = "ferramenta"; total = 0; simulando = simular;
            Executar("otimizar.ps1", a, !simular, reverter ? "Revertendo." : simular ? "Simulando " + nome + "." : "Aplicando " + nome + ".");
        };
        if (simular) rodar();
        else if (reverter) Confirmar("Reverter tudo?", "Serviços e registro voltam ao estado salvo. Apps removidos voltam em Ferramentas, Reinstalar apps removidos.", "Reverter", rodar);
        else Confirmar("Aplicar o nível " + nome + "?", "Um ponto de restauração é criado e o estado anterior fica salvo para reverter.", "Aplicar", rodar);
    }

    // ---------- ferramentas ----------

    void MontarFerramentas() {
        var p = C<StackPanel>("Ferramentas");
        FerramentaFormatar(p);
        Ferramenta(p, "atualizar", "Atualizar todos os programas", "winget upgrade --all --include-unknown");
        Ferramenta(p, "limpar", "Limpar disco", "Temporários, Lixeira, cache do Windows Update, componentes antigos (DISM), logs, miniaturas e cache dos navegadores. Mostra o espaço liberado.");
        Ferramenta(p, "reparar", "Reparar sistema", "DISM /RestoreHealth, sfc /scannow. Pode levar 30 minutos.");
        Ferramenta(p, "rede", "Resetar rede", "ipconfig /flushdns, netsh winsock reset, netsh int ip reset. Pede reinício.");
        Ferramenta(p, "restauracao", "Criar ponto de restauração", "Enable-ComputerRestore, Checkpoint-Computer");
        Ferramenta(p, "reinstalar-apps", "Reinstalar apps removidos", "winget install --source msstore, só os que faltam. Dicas, Paciência e Mapas não estão na loja.");
    }

    // As senhas do Wi-Fi iriam para a nuvem junto com a pasta.
    static bool PastaSincronizada(string pasta) {
        return new[] { "OneDrive", "OneDriveConsumer", "OneDriveCommercial" }.Select(Environment.GetEnvironmentVariable).Any(v => !string.IsNullOrEmpty(v) && pasta.StartsWith(v, StringComparison.OrdinalIgnoreCase));
    }

    void FerramentaFormatar(StackPanel p) {
        var g = new DockPanel();
        var b = new Button { Style = (Style)w.FindResource("BotaoPilula"), Content = "Rodar", VerticalAlignment = VerticalAlignment.Center };
        DockPanel.SetDock(b, Dock.Right);
        g.Children.Add(b);
        var t = new StackPanel();
        t.Children.Add(new TextoTrack { Texto = "Preparar formatação", Tamanho = 21, Track = -0.5, Familia = Fonte("FDisplay"), Cor = Tinta });
        t.Children.Add(Dado("Salva ao lado do app o que a instalação usa depois. Não apaga nada deste PC nem copia arquivos pessoais."));
        var opcoes = new WrapPanel { Margin = new Thickness(0, 10, 0, 0) };
        var caixas = new List<Marcavel>();
        // O Wi-Fi vem desmarcado: grava senhas em texto puro e precisa de uma decisão a cada uso.
        foreach (var o in new[] { new[] { "dados", "Dados do PC" }, new[] { "programas", "Programas" }, new[] { "rede", "Driver de rede" }, new[] { "loja", "Apps da Loja" }, new[] { "completos", "Todos os drivers" }, new[] { "wifi", "Wi-Fi com senhas" } }) {
            var cx = new CheckBox { Content = o[1], IsChecked = o[0] != "wifi", Margin = new Thickness(0, 0, 18, 4) };
            caixas.Add(new Marcavel { Id = o[0], Caixa = cx });
            opcoes.Children.Add(cx);
        }
        t.Children.Add(opcoes);
        g.Children.Add(t);
        b.Click += delegate {
            if (emAndamento || !podeAlterar) return;
            var itens = caixas.Where(c => c.Caixa.IsChecked == true).Select(c => c.Id).ToList();
            if (itens.Count == 0) { Aviso("Marque ao menos um item para preparar a formatação."); return; }
            string texto = "Nada é apagado deste PC. Os arquivos ficam em " + raiz + ".";
            if (itens.Contains("wifi")) {
                texto += " As senhas do Wi-Fi ficam em texto puro: guarde a pasta com cuidado. A instalação apaga os arquivos ao importar as redes.";
                if (PastaSincronizada(raiz)) texto += " Atenção: esta pasta está no OneDrive e as senhas iriam para a nuvem.";
            }
            Confirmar("Preparar formatação?", texto, "Preparar", delegate {
                abaDepois = "Ferramentas"; tipoExec = "ferramenta"; total = 0;
                Executar("antes-de-formatar.ps1", "-Itens " + string.Join(",", itens), true, "Preparar formatação.");
            });
        };
        p.Children.Add(Fila(g));
        w.Loaded += delegate { b.IsEnabled = podeAlterar; };
    }

    void Ferramenta(StackPanel p, string acao, string titulo, string det) {
        var g = new DockPanel();
        var b = new Button { Style = (Style)w.FindResource("BotaoPilula"), Content = "Rodar", VerticalAlignment = VerticalAlignment.Center };
        DockPanel.SetDock(b, Dock.Right);
        g.Children.Add(b);
        var t = new StackPanel();
        t.Children.Add(new TextoTrack { Texto = titulo, Tamanho = 21, Track = -0.5, Familia = Fonte("FDisplay"), Cor = Tinta });
        t.Children.Add(Dado(det));
        g.Children.Add(t);
        var i = acao; var ti = titulo;
        b.Click += delegate {
            if (emAndamento || !podeAlterar) return;
            Action rodar = delegate {
                abaDepois = "Ferramentas"; tipoExec = "ferramenta"; total = 0;
                Executar("ferramentas.ps1", "-Acao " + i, true, ti + ".");
            };
            if (i == "limpar") Confirmar("Limpar disco?", "Apaga temporários, caches do sistema e dos navegadores, logs antigos e miniaturas, e esvazia a Lixeira. Não toca em arquivos seus, senhas salvas nem no registro de execução do sistema.", "Limpar", rodar);
            else rodar();
        };
        botoesFerramenta.Add(b);
        p.Children.Add(Fila(g));
        w.Loaded += delegate { b.IsEnabled = podeAlterar; };
    }

    // ---------- anti-crash MTA ----------

    bool BackupMtaExiste() { return File.Exists(Path.Combine(dados, "mta-antes.json")); }

    void IniciarAnaliseMta() {
        if (emAndamento) return;
        abaDepois = "MTA"; tipoExec = "mta"; total = 5;
        Executar("mta-analisar.ps1", "", false, "Analisando o MTA.");
    }

    void CarregarMta() {
        var p = C<StackPanel>("PainelMta");
        p.Children.Clear(); correcoesMta.Clear();
        string arq = Path.Combine(dados, "mta.json");
        if (!File.Exists(arq)) { C<TextBlock>("ResumoMta").Text = "mta.json não foi gerado."; return; }
        var j = new JavaScriptSerializer { MaxJsonLength = int.MaxValue }.Deserialize<Dictionary<string, object>>(File.ReadAllText(arq, Encoding.UTF8));
        mtaAnalisado = true;
        if (!(bool)j["instalado"]) { C<TextBlock>("ResumoMta").Text = "MTA não encontrado neste PC."; return; }
        C<TextBlock>("ResumoMta").Text = "MTA " + (string)j["versao"] + "   " + Convert.ToInt32(j["redefinicoes"]) + " redefinições de vídeo na última sessão   " + (string)j["placa"];
        p.Children.Add(Secao("Último crash"));
        var crash = j["crash"] as Dictionary<string, object>;
        if (crash == null) p.Children.Add(Fila(new TextBlock { Text = "Nenhum crash registrado neste PC.", Foreground = Mudo, FontSize = 13 }));
        else {
            var st = new StackPanel();
            st.Children.Add(new TextBlock { Text = (string)crash["mensagem"], Foreground = Tinta, FontSize = 13, TextWrapping = TextWrapping.Wrap });
            st.Children.Add(Dado("Offset " + (string)crash["offset"] + "   código " + (string)crash["codigo"] + "   " + (string)crash["modulo"] + "   " + (string)crash["hora"] + "   é uma pista, não uma certeza"));
            p.Children.Add(Fila(st));
        }
        var avisos = (ArrayList)j["avisos"];
        if (avisos.Count > 0) p.Children.Add(Secao("Avisos"));
        foreach (string a in avisos) p.Children.Add(Fila(new TextBlock { Text = a, Foreground = Suave, FontSize = 13, TextWrapping = TextWrapping.Wrap }));
        var correcoes = (ArrayList)j["correcoes"];
        p.Children.Add(Secao("Correções"));
        if (correcoes.Count == 0) p.Children.Add(Fila(new TextBlock { Text = "Nada a corrigir.", Foreground = Mudo, FontSize = 13 }));
        foreach (Dictionary<string, object> c in correcoes) {
            var txt = new StackPanel();
            txt.Children.Add(new TextBlock { Text = (string)c["Rotulo"], FontSize = 13, Foreground = Tinta });
            txt.Children.Add(Dado((string)c["Detalhe"]));
            var cx = new CheckBox { IsChecked = (bool)c["Marcada"], Content = txt };
            cx.Click += delegate { AtualizarPainel(); };
            correcoesMta.Add(new Marcavel { Id = (string)c["Id"], Caixa = cx });
            p.Children.Add(Fila(cx));
        }
        p.Children.Add(Fila(Dado("Muitos crashes vêm de modelos e scripts do próprio servidor. Nenhum ajuste aqui evita esses, e nenhum altera arquivos do jogo.")));
    }

    void AplicarCorrecoesMta() {
        var ids = correcoesMta.Where(a => a.Caixa.IsChecked == true).Select(a => a.Id).ToList();
        if (ids.Count == 0 || emAndamento || !podeAlterarMta) return;
        string texto = "Feche o MTA antes. O estado atual fica salvo para reverter.";
        if (ids.Contains("componentes")) texto += " Componentes instalados não são removidos ao reverter.";
        Confirmar("Aplicar " + ids.Count + (ids.Count == 1 ? " item?" : " itens?"), texto, "Aplicar", delegate {
            // O diagnostico deixa de valer depois de aplicar: a proxima acao e analisar de novo.
            C<StackPanel>("PainelMta").Children.Clear(); correcoesMta.Clear(); mtaAnalisado = false;
            C<TextBlock>("ResumoMta").Text = "Analise de novo para conferir o resultado.";
            abaDepois = "MTA"; tipoExec = "ferramenta"; total = 0;
            Executar("mta-aplicar.ps1", "-Itens " + string.Join(",", ids), !semElevar, "Aplicando no MTA.");
        });
    }

    void ReverterCorrecoesMta() {
        if (emAndamento || !podeAlterarMta) return;
        Confirmar("Reverter?", "Feche o MTA antes. Configurações, placa de vídeo e mods voltam ao estado salvo. Componentes instalados não são removidos.", "Reverter", delegate {
            C<StackPanel>("PainelMta").Children.Clear(); correcoesMta.Clear(); mtaAnalisado = false;
            C<TextBlock>("ResumoMta").Text = "Analise de novo para conferir o resultado.";
            abaDepois = "MTA"; tipoExec = "ferramenta"; total = 0;
            Executar("mta-aplicar.ps1", "-Reverter", !semElevar, "Revertendo no MTA.");
        });
    }

    // ---------- paleta Ctrl K ----------

    void MontarPaleta() {
        var p = C<StackPanel>("AtalhosPaleta");
        foreach (var n in new[] { "instalar", "drivers", "analisar", "perfil gamer", "perfil dev" }) {
            var nome = n;
            var b = new Button { Style = (Style)w.FindResource("BotaoPilula"), Content = n, Margin = new Thickness(0, 0, 6, 0), Height = 28 };
            b.Click += delegate { C<TextBox>("EntradaPaleta").Text = nome; C<TextBox>("EntradaPaleta").Focus(); };
            p.Children.Add(b);
        }
    }

    void AbrirPaleta() {
        C<Grid>("Paleta").Visibility = Visibility.Visible;
        var e = C<TextBox>("EntradaPaleta");
        e.Text = "";
        AtualizarPaleta();
        e.Focus();
    }
    void FecharPaleta() { C<Grid>("Paleta").Visibility = Visibility.Collapsed; }

    void AtualizarPaleta() {
        string q = C<TextBox>("EntradaPaleta").Text.Trim().ToLower();
        var saida = C<StackPanel>("ResultadosPaleta");
        saida.Children.Clear(); acoesPaleta.Clear();
        var op = new List<KeyValuePair<string, Action>>();
        foreach (var a in new[] { "Instalar", "Drivers", "Analisar", "Otimizar", "Ferramentas", "MTA", "Terminal" }) { var n = a; op.Add(new KeyValuePair<string, Action>("ir " + a.ToLower(), delegate { C<RadioButton>("Aba" + n).IsChecked = true; })); }
        foreach (var a in new[] { "Completo", "Básico", "Gamer", "Dev", "IA" }) { var n = a; op.Add(new KeyValuePair<string, Action>("perfil " + a.ToLower(), delegate { C<RadioButton>("AbaInstalar").IsChecked = true; AplicarPerfil(n); })); }
        if (q.Length > 0) foreach (var g in grupos) foreach (var i in g.Itens) { var it = i; op.Add(new KeyValuePair<string, Action>((it.Caixa.IsChecked == true ? "desmarcar " : "marcar ") + it.Rotulo, delegate { C<RadioButton>("AbaInstalar").IsChecked = true; it.Caixa.IsChecked = it.Caixa.IsChecked != true; })); }
        var res = op.Where(o => q.Length == 0 || o.Key.ToLower().Contains(q)).Take(q.Length == 0 ? 3 : 8).ToList();
        if (q.Length == 0) {
            saida.Children.Add(new TextBlock { Text = "upaiva_ terminal", FontFamily = Mono, Foreground = Tinta, FontSize = 12.5 });
            saida.Children.Add(new TextBlock { Text = "digite um programa, um perfil ou uma seção.", FontFamily = Mono, Foreground = Mudo, FontSize = 12.5, Margin = new Thickness(0, 10, 0, 0) });
            return;
        }
        if (res.Count == 0) { saida.Children.Add(new TextBlock { Text = "nada encontrado para \"" + q + "\".", FontFamily = Mono, Foreground = Mudo, FontSize = 12.5 }); return; }
        bool primeiro = true;
        foreach (var r in res) {
            var ac = r.Value; acoesPaleta.Add(ac);
            var t = new TextBlock { Text = (primeiro ? "> " : "  ") + r.Key, FontFamily = Mono, FontSize = 12.5, Foreground = primeiro ? Tinta : Mudo, Margin = new Thickness(0, 0, 0, 7), Cursor = Cursors.Hand };
            t.MouseLeftButtonUp += delegate { FecharPaleta(); ac(); };
            saida.Children.Add(t);
            primeiro = false;
        }
    }

    // ---------- execucao ----------

    void Executar(string script, string argumentos, bool elevado, string titulo) {
        Directory.CreateDirectory(Path.GetDirectoryName(logPath));
        try { if (File.Exists(flagCancelar)) File.Delete(flagCancelar); } catch { }
        posicaoLog = File.Exists(logPath) ? new FileInfo(logPath).Length : 0;
        resto = ""; concluidas = 0; feitas = 0; falhas = 0; terminado = false; cancelando = false;
        linhas.Clear();
        C<StackPanel>("Etapas").Children.Clear();
        string cmd = "-NoProfile -ExecutionPolicy Bypass -File \"" + Path.Combine(raiz, "scripts", script) + "\" " + argumentos;
        ProcessStartInfo psi;
        if (elevado) psi = new ProcessStartInfo("powershell.exe", cmd) { UseShellExecute = true, Verb = "runas", WindowStyle = ProcessWindowStyle.Hidden };
        else {
            psi = new ProcessStartInfo("powershell.exe", cmd) { UseShellExecute = false, CreateNoWindow = true };
            psi.EnvironmentVariables["SETUP_GUI"] = "1";
            psi.EnvironmentVariables["SETUP_DADOS"] = dados;
            psi.EnvironmentVariables.Remove("PSModulePath");
        }
        Term("$ powershell " + cmd.Replace(raiz + "\\", ""));
        try { processo = Process.Start(psi); }
        catch (Win32Exception e) { Term("exec.denied " + e.Message); Aviso("O Windows não recebeu permissão de administrador. Nada foi feito."); return; }
        emAndamento = true;
        inicioExec = DateTime.Now;
        Term("proc.spawn pid=" + processo.Id + " elevated=" + elevado);
        situacao = titulo;
        C<RadioButton>("AbaTerminal").IsChecked = true;
        TrocarAba("Terminal");
        TituloExec(titulo, total > 0 ? "0%" : "Em andamento.");
        planeta.Ativo = true; planeta.Progresso = simulando ? -1 : 0;
        C<Border>("BarraProgresso").Width = 0;
        C<Button>("Cancelar").Visibility = Visibility.Visible;
        C<Button>("Cancelar").IsEnabled = true;
        C<Button>("Relatorio").Visibility = Visibility.Collapsed;
        AtualizarPainel();
        relogio = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(350) };
        relogio.Tick += delegate { LerLog(); if (processo.HasExited) { relogio.Stop(); LerLog(); Finalizar(); } };
        relogio.Start();
    }

    void PedirCancelamento() {
        if (!emAndamento || cancelando) return;
        cancelando = true;
        try { Directory.CreateDirectory(dados); File.WriteAllText(flagCancelar, DateTime.Now.ToString("s")); } catch { }
        Term("cancel.requested: o comando atual é encerrado e os próximos são ignorados");
        C<Button>("Cancelar").IsEnabled = false;
        TituloExec("Cancelando.", "Encerrando o comando atual.");
    }

    void Term(string l) {
        var t = C<RichTextBox>("Terminal");
        Brush cor = Mudo;
        if (l.StartsWith("$ ")) cor = Tinta;
        else if (l.StartsWith("[....]")) cor = Suave;
        else if (l.StartsWith("  |")) cor = Fraco;
        else if (l.StartsWith("[FALHOU]") || l.Contains("policy.deny") || l.StartsWith("ui.error") || l.StartsWith("exec.denied")) cor = Sinal;
        // Linha longa quebra alinhada depois do horario.
        var p = new Paragraph { Margin = new Thickness(69, 0, 0, 0), TextIndent = -69, LineHeight = 17 };
        p.Inlines.Add(new Run(DateTime.Now.ToString("HH:mm:ss") + "  ") { Foreground = Fraco });
        p.Inlines.Add(new Run(l) { Foreground = cor });
        t.Document.Blocks.Add(p);
        while (t.Document.Blocks.Count > 900) t.Document.Blocks.Remove(t.Document.Blocks.FirstBlock);
        t.ScrollToEnd();
    }

    void LerLog() {
        if (!File.Exists(logPath)) return;
        FileStream f;
        // Um script pode estar com o arquivo aberto neste instante: a proxima leitura pega o que faltou.
        try { f = new FileStream(logPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete); }
        catch (IOException) { return; }
        using (f) {
            if (f.Length <= posicaoLog) return;
            f.Seek(posicaoLog, SeekOrigin.Begin);
            var b = new byte[f.Length - posicaoLog];
            int n = f.Read(b, 0, b.Length);
            posicaoLog += n;
            string texto = resto + Encoding.UTF8.GetString(b, 0, n).Replace("\uFEFF", "");
            int fim = texto.LastIndexOf('\n');
            if (fim < 0) { resto = texto; return; }
            resto = texto.Substring(fim + 1);
            foreach (var l in texto.Substring(0, fim).Split('\n')) ProcessarLinha(l.TrimEnd('\r'));
        }
    }

    static readonly Regex RxLinha = new Regex(@"^\d\d:\d\d:\d\d (.*)$");

    void Conta(string etapa) { int p; concluidas += pesos.TryGetValue(etapa, out p) ? p : 1; feitas++; }

    void ProcessarLinha(string bruta) {
        var m = RxLinha.Match(bruta);
        string l = m.Success ? m.Groups[1].Value : bruta;
        if (l.Length == 0 || l.StartsWith("[ignorado] ")) return;
        // Na simulacao nada e aplicado: o terminal nao pode dizer "ok" nem repetir o comando como se rodasse.
        if (simulando && l.StartsWith("[....] ")) { var n = l.Substring(7); Marcar(n, ">>", Tinta, ""); linhas[n].Inicio = DateTime.Now; return; }
        if (l.StartsWith("@total ")) { int v; if (int.TryParse(l.Substring(7), out v) && tipoExec != "instalar") total = v; return; }
        Term(simulando && l.StartsWith("[ ok ] ") ? "[ sim ] " + l.Substring(7) : l);
        if (l.StartsWith("[....] ")) { var n = l.Substring(7); Marcar(n, ">>", Tinta, ""); linhas[n].Inicio = DateTime.Now; situacao = Nome(n); }
        else if (l.StartsWith("[ ok ] ")) { var n = l.Substring(7); Marcar(n, simulando ? "SIM" : "OK", Suave, Tempo(n)); Conta(n); }
        else if (l.StartsWith("[pulado] ")) { var n = l.Substring(9).Replace(" (já feito)", ""); Marcar(n, "OK", Mudo, "já feito"); Conta(n); }
        else if (l.StartsWith("[cancelado] ")) { var n = l.Substring(12); Marcar(n, "--", Fraco, "cancelado"); Conta(n); }
        else if (l.StartsWith("[FALHOU] ")) {
            string r = l.Substring(9); int s = r.IndexOf(" - ");
            string n = s >= 0 ? r.Substring(0, s) : r, d = s >= 0 ? r.Substring(s + 3) : "";
            Marcar(n, "!!", Sinal, d.Replace("FALHA: ", "")); falhas++; Conta(n);
        }
        else if (l.StartsWith("Sem internet")) Aviso(l);
        else if (l.StartsWith("Etapa ")) situacao = l;
        Progresso();
    }

    string Tempo(string etapa) {
        Linha x;
        if (!linhas.TryGetValue(etapa, out x) || x.Inicio == DateTime.MinValue) return "";
        var t = DateTime.Now - x.Inicio;
        return t.TotalSeconds < 1 ? "" : t.TotalMinutes >= 1 ? ((int)t.TotalMinutes) + "m " + t.Seconds + "s" : ((int)t.TotalSeconds) + "s";
    }

    void Progresso() {
        if (simulando) { if (!cancelando) TituloExec(tituloExec1, feitas + " de " + total + " ações do plano."); return; }
        double pct = total > 0 ? Math.Min(0.99, concluidas / (double)total) : 0;
        planeta.Progresso = pct;
        C<Border>("BarraProgresso").Width = Math.Max(0, (w.ActualWidth - 74) * pct);
        if (!cancelando) {
            var pend = linhas.Values.Count(x => x.Etiqueta.Text == "[..]");
            // Sem total conhecido nao ha porcentagem honesta para mostrar.
            int ativos = linhas.Values.Count(x => x.Etiqueta.Text == "[>>]");
            TituloExec(ativos > 1 ? ativos + " instalando juntos." : Curto(situacao), total > 0 ? ((int)(pct * 100)) + "%" + (pend > 0 ? ", faltam " + pend : "") : "Em andamento.");
        }
    }

    static string Curto(string t) {
        int p = t.IndexOf(". ");
        if (p > 0) t = t.Substring(0, p);
        return t.Length > 32 ? t.Substring(0, 31).TrimEnd() + "\u2026" : t;
    }

    static readonly Regex RxReg = new Regex(@"^(reg\.\w+) .*\\([^\\\s]+)");

    string Nome(string etapa) {
        string r;
        var mr = RxReg.Match(etapa);
        if (mr.Success) return mr.Groups[1].Value + " " + mr.Groups[2].Value;
        if (rotulos.TryGetValue(etapa, out r)) return r;
        return etapa.StartsWith("Programa ") ? etapa.Substring(9) : etapa;
    }

    void Marcar(string etapa, string etiqueta, Brush cor, string detalhe) {
        Linha l;
        if (!linhas.TryGetValue(etapa, out l)) {
            l = new Linha {
                Etiqueta = new TextBlock { FontFamily = Mono, FontSize = 11.5, Width = 38, VerticalAlignment = VerticalAlignment.Center },
                Texto = new TextBlock { Text = Nome(etapa), FontSize = 12.5, VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis },
                Detalhe = new TextBlock { FontFamily = Mono, Foreground = Mudo, FontSize = 11, VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis, Margin = new Thickness(10, 0, 0, 0), MaxWidth = 170 }
            };
            var linha = new DockPanel { Margin = new Thickness(0, 0, 0, 5) };
            DockPanel.SetDock(l.Etiqueta, Dock.Left);
            DockPanel.SetDock(l.Detalhe, Dock.Right);
            linha.Children.Add(l.Etiqueta); linha.Children.Add(l.Detalhe); linha.Children.Add(l.Texto);
            C<StackPanel>("Etapas").Children.Add(linha);
            linhas[etapa] = l;
        }
        l.Etiqueta.Text = "[" + etiqueta + "]"; l.Etiqueta.Foreground = cor;
        l.Texto.Foreground = etiqueta == ".." ? Fraco : etiqueta == ">>" ? Tinta : etiqueta == "!!" ? Sinal : Suave;
        l.Detalhe.Text = detalhe;
        // Motivo de falha aparece inteiro.
        l.Detalhe.TextWrapping = etiqueta == "!!" ? TextWrapping.Wrap : TextWrapping.NoWrap;
        l.Detalhe.MaxWidth = etiqueta == "!!" ? 230 : 170;
        if (etiqueta == ">>") l.Texto.BringIntoView();
    }

    void Finalizar() {
        emAndamento = false;
        terminado = true;
        planeta.Ativo = false;
        C<Button>("Cancelar").Visibility = Visibility.Collapsed;
        int codigo = 0; try { codigo = processo.ExitCode; } catch { }
        Term("proc.exit code=" + codigo + " elapsed=" + (DateTime.Now - inicioExec).ToString(@"hh\:mm\:ss"));
        int falhou = falhas, manual = 0;
        var apontados = new List<string>();
        if (tipoExec == "instalar" && File.Exists(relatorioPath)) {
            falhou = 0;
            foreach (var x in File.ReadAllLines(relatorioPath, Encoding.UTF8)) {
                if (x.StartsWith("FALHOU")) { falhou++; apontados.Add(x.Substring(6).Trim()); }
                else if (x.StartsWith("MANUAL")) manual++;
            }
            C<Button>("Relatorio").Visibility = Visibility.Visible;
        }
        // O que ficou na fila nao rodou: mostrar como concluido seria mentira.
        int naoRodou = 0;
        foreach (var v in linhas.Values.Where(x => x.Etiqueta.Text == "[..]" || x.Etiqueta.Text == "[>>]")) { v.Etiqueta.Text = "[--]"; v.Etiqueta.Foreground = Fraco; v.Detalhe.Text = "não rodou"; v.Texto.Foreground = Fraco; naoRodou++; }
        bool limpo = !cancelando && !simulando && falhou == 0 && codigo == 0 && naoRodou == 0;
        double real = total > 0 ? Math.Min(1.0, concluidas / (double)total) : 0;
        // A orbita so acende enquanto algo roda. A barra guarda o quanto foi feito de verdade.
        planeta.Progresso = -1;
        C<Border>("BarraProgresso").Width = simulando ? 0 : (w.ActualWidth - 74) * (limpo ? 1 : real);
        if (cancelando) TituloExec("Cancelado.", "Rode de novo: refaz só o que faltou.");
        else if (falhou > 0) TituloExec(falhou + (falhou == 1 ? " item falhou." : " itens falharam."), "Rode de novo: refaz só o que faltou.");
        else if (codigo != 0) TituloExec("Terminou com erro.", "Código de saída " + codigo + ".");
        else if (naoRodou > 0) TituloExec(naoRodou + (naoRodou == 1 ? " item não rodou." : " itens não rodaram."), "Rode de novo: refaz só o que faltou.");
        else if (simulando) TituloExec("Simulação concluída.", "Nada foi alterado.");
        else TituloExec("Concluído.", tipoExec == "instalar" ? "Reinicie e faça login." : "Veja a saída no terminal.");
        simulando = false;
        if (manual > 0) Aviso("Falta instalar à mão: veja o relatório.");
        try { if (File.Exists(flagCancelar)) File.Delete(flagCancelar); } catch { }
        if (tipoExec == "analisar") CarregarAchados();
        if (tipoExec == "drivers") CarregarDrivers();
        if (tipoExec == "mta") CarregarMta();
        AtualizarPainel();
        if (arqFotoFim != null) {
            var t = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(1500) };
            t.Tick += delegate {
                t.Stop();
                if (tipoExec == "analisar") { terminado = false; C<RadioButton>("AbaAnalisar").IsChecked = true; }
                if (tipoExec == "drivers") { terminado = false; C<RadioButton>("AbaDrivers").IsChecked = true; }
                if (tipoExec == "mta") { terminado = false; C<RadioButton>("AbaMTA").IsChecked = true; }
                w.Dispatcher.BeginInvoke(DispatcherPriority.Background, new Action(delegate {
                    Fotografar(arqFotoFim);
                    File.WriteAllText(arqFotoFim + ".txt", "falhou=" + falhou + " manual=" + manual + " linhas=" + linhas.Count + " feitas=" + feitas + " peso=" + concluidas + "/" + total + " term=" + C<RichTextBox>("Terminal").Document.Blocks.Count + " cancelado=" + cancelando + " codigo=" + codigo + " naoRodou=" + naoRodou + " mta=" + mtaAnalisado + "/" + correcoesMta.Count(a => a.Caixa.IsChecked == true) + "/" + podeAlterarMta + "/" + podeAlterar + " reverterMta=" + (C<Button>("ReverterMta").Visibility == Visibility.Visible));
                    Application.Current.Shutdown();
                }));
            };
            t.Start();
        }
    }

    void Demonstrar() {
        total = 14; tipoExec = "ferramenta"; emAndamento = true; inicioExec = DateTime.Now.AddMinutes(-7);
        C<RadioButton>("AbaTerminal").IsChecked = true;
        planeta.Ativo = true; planeta.Progresso = 0;
        C<Button>("Cancelar").Visibility = Visibility.Visible;
        AtualizarPainel();
        foreach (var l in new[] {
            "10:00:01 Etapa 1 de 3: programas do sistema. Clique em Sim no aviso do Windows.",
            "10:00:02 [ ok ] Drivers de rede",
            "10:00:03 [ ok ] Programa Microsoft.VCRedist.2015+.x64",
            "10:00:04 [pulado] Programa Microsoft.DirectX (já feito)",
            "10:00:05 [ ok ] Programa Google.Chrome",
            "10:00:06 [FALHOU] Programa Microsoft.XNARedist - FALHA: não aparece no winget (código 1460)",
            "10:00:08 [....] Programa Discord.Discord",
            "10:00:08 $ winget.exe install --id \"Discord.Discord\" --exact --source winget --silent",
            "10:00:08 proc.spawn pid=18244 timeout=25m",
            "10:00:11   | Found Discord [Discord.Discord] Version 1.0.9267",
            "10:00:12   | Successfully verified installer hash" }) ProcessarLinha(l);
        foreach (var e in new[] { "Programa Microsoft.VisualStudio.BuildTools", "Programa OpenAI.Codex", "Programa Spotify.Spotify" }) Marcar(e, "..", Fraco, "");
        Progresso();
    }
}
}
