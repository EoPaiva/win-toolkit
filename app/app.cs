using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
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
using System.Windows.Controls.Primitives;
using System.Windows.Documents;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

[assembly: AssemblyTitle("upaiva.dev")]
[assembly: AssemblyProduct("upaiva.dev")]
[assembly: AssemblyDescription("upaiva.dev")]
[assembly: AssemblyVersion("1.1.0.0")]

// Interface: nao altera nada sozinha. Chama os scripts e acompanha o log que eles escrevem, inclusive os elevados,
// que rodam em outro processo. Status, comandos e telemetria mostrados na tela sao reais.
class Item { public string Rotulo, Id; public List<string> Padroes = new List<string>(); public int Peso = 1; public CheckBox Caixa; public bool Catalogo; }
class Grupo { public string Nome; public List<Item> Itens = new List<Item>(); public CheckBox Caixa; public TextBlock Contador; public bool Catalogo; }
class Linha { public TextBlock Etiqueta, Texto, Detalhe; }

class Achado { public string Id; public CheckBox Caixa; }

static class Nativo {
    [StructLayout(LayoutKind.Sequential)] public struct FT { public uint Low, High; public ulong V { get { return ((ulong)High << 32) | Low; } } }
    [DllImport("kernel32.dll")] public static extern bool GetSystemTimes(out FT idle, out FT kernel, out FT user);
    [StructLayout(LayoutKind.Sequential)] public class MEM { public uint dwLength = 64, dwMemoryLoad; public ulong total, avail, tp, ap, tv, av, ave; }
    [DllImport("kernel32.dll")] public static extern bool GlobalMemoryStatusEx([In, Out] MEM m);
}

// Rede de nos ao fundo. E so decoracao e fica atras de todo o conteudo.
class RedeFundo : FrameworkElement {
    class No { public double X, Y, Vx, Vy; }
    readonly List<No> nos = new List<No>();
    readonly Pen[] canetas = new Pen[6];
    readonly Brush ponto;
    public RedeFundo(double w, double h) {
        IsHitTestVisible = false;
        var r = new Random(7);
        for (int i = 0; i < 52; i++) nos.Add(new No { X = r.NextDouble() * w, Y = r.NextDouble() * h, Vx = (r.NextDouble() - 0.5) * 0.7, Vy = (r.NextDouble() - 0.5) * 0.7 });
        for (int i = 0; i < 6; i++) { var b = new SolidColorBrush(Color.FromArgb((byte)(10 + i * 11), 34, 211, 238)); b.Freeze(); canetas[i] = new Pen(b, 1); canetas[i].Freeze(); }
        var p = new SolidColorBrush(Color.FromArgb(150, 94, 234, 212)); p.Freeze(); ponto = p;
    }
    public void Avancar() {
        double w = ActualWidth, h = ActualHeight;
        if (w <= 0) return;
        foreach (var n in nos) { n.X += n.Vx; n.Y += n.Vy; if (n.X < 0 || n.X > w) n.Vx = -n.Vx; if (n.Y < 0 || n.Y > h) n.Vy = -n.Vy; }
        InvalidateVisual();
    }
    protected override void OnRender(DrawingContext dc) {
        const double alcance = 150;
        for (int i = 0; i < nos.Count; i++) {
            var a = nos[i];
            for (int j = i + 1; j < nos.Count; j++) {
                var b = nos[j];
                double dx = a.X - b.X, dy = a.Y - b.Y, d = dx * dx + dy * dy;
                if (d < alcance * alcance) dc.DrawLine(canetas[(int)((1 - Math.Sqrt(d) / alcance) * 5.99)], new Point(a.X, a.Y), new Point(b.X, b.Y));
            }
            dc.DrawEllipse(ponto, null, new Point(a.X, a.Y), 1.6, 1.6);
        }
    }
}

class Aplicativo {
    Window w;
    string raiz, dados, logPath, relatorioPath, arqFotoFim, abaAtual = "Instalar", abaDepois;
    List<Grupo> grupos = new List<Grupo>();
    Dictionary<string, string> rotulos = new Dictionary<string, string>();
    Dictionary<string, Linha> linhas = new Dictionary<string, Linha>();
    List<Achado> achados = new List<Achado>();
    long posicaoLog;
    string resto = "", alvoDigitado = "", situacaoBase = "", nivelEscolhido = "media", tipoExec = "";
    int total, concluidas, falhas, digitados, quadro;
    Process processo;
    DispatcherTimer relogio, animacao;
    bool emAndamento, atualizando, terminado, podeAlterar = true, semElevar;
    List<Achado> driversMarcaveis = new List<Achado>();
    List<long> amostrasCpu = new List<long>();
    RedeFundo rede;
    DateTime inicioExec;
    ulong antIdle, antTotal; long antRede; DateTime antRedeT = DateTime.Now;


    static readonly FontFamily Mono = new FontFamily("Cascadia Mono, Consolas");
    static readonly Brush Apagado = Cor("#6B7690"), Medio = Cor("#AEB8CC"), Destaque = Cor("#22D3EE"), Bom = Cor("#34D399"), Vermelho = Cor("#F87171"), Ciano = Cor("#22D3EE"), Laranja = Cor("#FBBF24"), Amarelo = Cor("#FDE68A"), Violeta = Cor("#A78BFA");
    static SolidColorBrush Cor(string h) { return (SolidColorBrush)new BrushConverter().ConvertFromString(h); }
    T C<T>(string nome) where T : class { return w.FindName(nome) as T; }

    [STAThread]
    static int Main(string[] args) {
        try { new Aplicativo().Rodar(args); return 0; }
        catch (Exception e) { MessageBox.Show(e.ToString(), "upaiva.dev", MessageBoxButton.OK, MessageBoxImage.Error); return 1; }
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

        var app = new Application();
        // A instalacao roda em outro processo: um erro de tela nao pode fechar a janela que a acompanha.
        app.DispatcherUnhandledException += (o, e) => { e.Handled = true; try { Term("ui.error " + e.Exception.Message); } catch { } };
        using (var s = Assembly.GetExecutingAssembly().GetManifestResourceStream("ui.xaml"))
        using (var r = new StreamReader(s, Encoding.UTF8)) w = (Window)XamlReader.Parse(r.ReadToEnd());

        rede = new RedeFundo(w.Width, w.Height);
        C<Grid>("FundoHost").Children.Insert(2, rede);
        var termo = C<RichTextBox>("Terminal");
        termo.Document = new FlowDocument { PagePadding = new Thickness(4), PageWidth = 3000, FontFamily = Mono, FontSize = 11.5 };
        C<TextBlock>("Host").Text = Environment.MachineName + " · " + Environment.UserName;
        CarregarLista();
        MontarGrupos();
        MontarPerfis();
        MontarFerramentas();
        C<TextBlock>("Situacao").Text = "Skills e configs vêm deste kit. Logins, projetos e logs não vêm.";
        Digitar("upaiva › pronto");

        C<Grid>("Topo").MouseLeftButtonDown += delegate { w.DragMove(); };
        C<Button>("Minimizar").Click += delegate { w.WindowState = WindowState.Minimized; };
        C<Button>("Fechar").Click += delegate { w.Close(); };
        C<Button>("Principal").Click += delegate { BotaoPrincipal(); };
        C<Button>("Relatorio").Click += delegate { if (File.Exists(relatorioPath)) Process.Start("notepad.exe", "\"" + relatorioPath + "\""); };
        C<Button>("Simular").Click += delegate { RodarOtimizar(true, false); };
        C<Button>("Reverter").Click += delegate { RodarOtimizar(false, true); };
        C<Button>("Corrigir").Click += delegate { CorrigirMarcados(); };
        C<Button>("InstalarDrivers").Click += delegate { InstalarDriversMarcados(); };
        foreach (var a in new[] { "Instalar", "Drivers", "Analisar", "Otimizar", "Ferramentas", "Terminal" }) { var n = a; C<RadioButton>("Aba" + a).Checked += delegate { TrocarAba(n); }; }
        w.Closing += (o, e) => {
            if (emAndamento && MessageBox.Show(w, "Ainda está rodando. Fechar esta janela não interrompe o que já começou. Fechar mesmo assim?", "upaiva.dev", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) e.Cancel = true;
        };

        // Instalar ou otimizar aqui alteraria o PC de origem das configs. Analisar e simular so leem.
        if (string.Equals(Environment.GetEnvironmentVariable("COMPUTERNAME"), "MARINETE", StringComparison.OrdinalIgnoreCase)) { podeAlterar = false; AvisoFixo("Somente leitura: este é o PC de origem das configs. Aqui só funcionam Analisar, Simular e Buscar drivers."); }
        else if (new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator)) { podeAlterar = false; AvisoFixo("Abra com dois cliques, sem \"Executar como administrador\": alguns programas recusam instalar elevados. O Windows pede permissão na hora certa."); }

        string foto = Arg(args, "--foto"), demo = Arg(args, "--demo"), aba = Arg(args, "--aba"), autoSim = Arg(args, "--auto-simular");
        arqFotoFim = Arg(args, "--foto-fim");
        w.Loaded += delegate {
            IniciarAnimacoes();
            TrocarAba(abaAtual);
            if (aba != null) C<RadioButton>("Aba" + aba).IsChecked = true;
            if (demo == "progresso") Demonstrar();
            if (args.Contains("--auto")) w.Dispatcher.BeginInvoke(DispatcherPriority.Background, new Action(IniciarInstalacao));
            if (args.Contains("--auto-analisar")) w.Dispatcher.BeginInvoke(DispatcherPriority.Background, new Action(IniciarAnalise));
            if (args.Contains("--auto-drivers")) w.Dispatcher.BeginInvoke(DispatcherPriority.Background, new Action(IniciarBuscaDrivers));
            if (autoSim != null) { nivelEscolhido = autoSim; w.Dispatcher.BeginInvoke(DispatcherPriority.Background, new Action(delegate { RodarOtimizar(true, false); })); }
            if (foto != null) { var t = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(2800) }; t.Tick += delegate { t.Stop(); Fotografar(foto); app.Shutdown(); }; t.Start(); }
        };
        app.Run(w);
    }

    void AvisoFixo(string m) { var a = C<TextBlock>("Aviso"); a.Text = m; a.Foreground = Vermelho; a.Visibility = Visibility.Visible; }

    void Fotografar(string arq) {
        var el = (FrameworkElement)w.Content;
        var bmp = new RenderTargetBitmap((int)el.ActualWidth, (int)el.ActualHeight, 96, 96, PixelFormats.Pbgra32);
        bmp.Render(el);
        var enc = new PngBitmapEncoder();
        enc.Frames.Add(BitmapFrame.Create(bmp));
        using (var f = File.Create(arq)) enc.Save(f);
    }

    // ---------- abas ----------

    void TrocarAba(string a) {
        abaAtual = a;
        C<TextBlock>("TituloSecao").Text = a;
        C<ScrollViewer>("RolagemGrupos").Visibility = a == "Instalar" ? Visibility.Visible : Visibility.Collapsed;
        C<DockPanel>("VisaoDrivers").Visibility = a == "Drivers" ? Visibility.Visible : Visibility.Collapsed;
        C<DockPanel>("VisaoAnalisar").Visibility = a == "Analisar" ? Visibility.Visible : Visibility.Collapsed;
        C<DockPanel>("VisaoOtimizar").Visibility = a == "Otimizar" ? Visibility.Visible : Visibility.Collapsed;
        C<ScrollViewer>("VisaoFerramentas").Visibility = a == "Ferramentas" ? Visibility.Visible : Visibility.Collapsed;
        C<Grid>("MolduraEtapas").Visibility = a == "Terminal" ? Visibility.Visible : Visibility.Collapsed;
        AtualizarPainel();
    }

    void AtualizarPainel() {
        var b = C<Button>("Principal");
        var num = C<TextBlock>("NumeroGrande");
        var leg = C<TextBlock>("LegendaGrande");
        b.Visibility = Visibility.Visible;
        if (emAndamento) { b.Content = "Em execução..."; b.IsEnabled = false; return; }
        if (abaAtual == "Terminal") { if (terminado) { b.Content = "Voltar"; b.IsEnabled = true; } else b.Visibility = Visibility.Collapsed; return; }
        C<ProgressBar>("Barra").Visibility = Visibility.Collapsed;
        C<Button>("Relatorio").Visibility = Visibility.Collapsed;
        if (abaAtual == "Instalar") { b.Content = "Instalar selecionados"; b.IsEnabled = podeAlterar; Recontar(); leg.Text = "módulos selecionados"; }
        else if (abaAtual == "Drivers") { b.Content = "Buscar drivers"; b.IsEnabled = true; if (driversMarcaveis.Count == 0 && C<StackPanel>("ListaDrivers").Children.Count == 0) { num.Text = "---"; leg.Text = "sem busca ainda"; } }
        else if (abaAtual == "Analisar") { b.Content = "Iniciar análise"; b.IsEnabled = true; if (achados.Count == 0 && C<StackPanel>("Achados").Children.Count == 0) { num.Text = "---"; leg.Text = "sem análise ainda"; } }
        else if (abaAtual == "Otimizar") { b.Content = "Aplicar nível"; b.IsEnabled = podeAlterar; num.Text = nivelEscolhido == "altissima" ? "Altíssima" : nivelEscolhido == "media" ? "Média" : nivelEscolhido == "alta" ? "Alta" : "Leve"; leg.Text = "nível selecionado"; }
        else { b.Visibility = Visibility.Collapsed; num.Text = "---"; leg.Text = "escolha uma rotina"; }
    }

    void BotaoPrincipal() {
        if (emAndamento) return;
        if (abaAtual == "Terminal") { terminado = false; C<RadioButton>("Aba" + (abaDepois ?? "Instalar")).IsChecked = true; C<TextBlock>("Situacao").Foreground = Medio; return; }
        if (abaAtual == "Instalar") IniciarInstalacao();
        else if (abaAtual == "Drivers") IniciarBuscaDrivers();
        else if (abaAtual == "Analisar") IniciarAnalise();
        else if (abaAtual == "Otimizar") RodarOtimizar(false, false);
    }

    // ---------- animacao e telemetria ----------

    void IniciarAnimacoes() {
        animacao = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(40) };
        animacao.Tick += delegate { Animar(); };
        animacao.Start();
        Flutuar("MoveAurora1", 70, 40, 19);
        Flutuar("MoveAurora2", -80, -50, 23);
        Telemetria();
    }

    void Flutuar(string nome, double x, double y, int seg) {
        var t = w.FindName(nome) as TranslateTransform;
        if (t == null) return;
        t.BeginAnimation(TranslateTransform.XProperty, new DoubleAnimation(0, x, new Duration(TimeSpan.FromSeconds(seg))) { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever });
        t.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(0, y, new Duration(TimeSpan.FromSeconds(seg + 5))) { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever });
    }

    void Animar() {
        if (w.WindowState == WindowState.Minimized) return;
        quadro++;
        if (rede != null) rede.Avancar();
        if (quadro % 2 == 0 && digitados < alvoDigitado.Length) digitados++;
        C<TextBlock>("Subtitulo").Text = alvoDigitado.Substring(0, digitados) + ((quadro / 12) % 2 == 0 ? "▌" : " ");
        C<System.Windows.Shapes.Ellipse>("Pulso").Opacity = emAndamento ? 0.35 + 0.65 * Math.Abs(Math.Sin(quadro * 0.07)) : 1;
        C<TextBlock>("Estado").Text = emAndamento ? "em execução" : "online";
        if (quadro % 25 == 0) Telemetria();
        if (emAndamento && situacaoBase.Length > 0) C<TextBlock>("Situacao").Text = situacaoBase;
    }

    // Desenha o arco do anel a partir das 12 horas.
    static void Anel(System.Windows.Shapes.Path p, double pct) {
        const double c = 48, r = 44;
        pct = Math.Max(0.5, Math.Min(99.9, pct));
        double a = pct / 100 * 2 * Math.PI;
        var g = new StreamGeometry();
        using (var ctx = g.Open()) {
            ctx.BeginFigure(new Point(c, c - r), false, false);
            ctx.ArcTo(new Point(c + r * Math.Sin(a), c - r * Math.Cos(a)), new Size(r, r), 0, pct > 50, SweepDirection.Clockwise, true, false);
        }
        g.Freeze();
        p.Data = g;
    }

    void Telemetria() {
        Nativo.FT i, k, u;
        if (Nativo.GetSystemTimes(out i, out k, out u)) {
            ulong tot = k.V + u.V;
            if (antTotal > 0 && tot > antTotal) {
                long v = Math.Max(0, 100 - (long)((i.V - antIdle) * 100 / (tot - antTotal)));
                C<TextBlock>("ValorCpu").Text = v + "%";
                Anel(C<System.Windows.Shapes.Path>("AnelCpu"), v);
                amostrasCpu.Add(v);
                if (amostrasCpu.Count > 60) amostrasCpu.RemoveAt(0);
                var pts = new PointCollection();
                for (int n = 0; n < amostrasCpu.Count; n++) pts.Add(new Point(n * (250.0 / 59), 29 - amostrasCpu[n] * 0.28));
                C<System.Windows.Shapes.Polyline>("Sparkline").Points = pts;
            }
            antIdle = i.V; antTotal = tot;
        }
        var m = new Nativo.MEM();
        Nativo.GlobalMemoryStatusEx(m);
        C<TextBlock>("ValorRam").Text = m.dwMemoryLoad + "%";
        Anel(C<System.Windows.Shapes.Path>("AnelRam"), m.dwMemoryLoad);
        long bytesRede = 0;
        try { foreach (var n in NetworkInterface.GetAllNetworkInterfaces()) if (n.OperationalStatus == OperationalStatus.Up && n.NetworkInterfaceType != NetworkInterfaceType.Loopback) bytesRede += n.GetIPv4Statistics().BytesReceived; } catch { }
        double seg = Math.Max(0.1, (DateTime.Now - antRedeT).TotalSeconds);
        double mbps = antRede > 0 ? Math.Max(0, (bytesRede - antRede) * 8 / 1000000.0 / seg) : 0;
        antRede = bytesRede; antRedeT = DateTime.Now;
        string tempo = emAndamento ? (DateTime.Now - inicioExec).ToString(@"hh\:mm\:ss") : "idle";
        string pid = emAndamento && processo != null ? processo.Id.ToString() : "--";
        C<TextBlock>("Telemetria").Text = "net    " + mbps.ToString("0.0") + " Mbps · " + (m.total / 1073741824) + " GB RAM\npid    " + pid + "\ntempo  " + tempo;
    }

void Digitar(string texto) { alvoDigitado = texto; digitados = 0; }

    // ---------- drivers ----------

    void IniciarBuscaDrivers() {
        if (emAndamento) return;
        abaDepois = "Drivers"; tipoExec = "drivers"; total = 4;
        Executar("drivers.ps1", "-Acao buscar", false, "upaiva › drivers --scan --source windows-update");
    }

    TextBlock Rotulo(string t) { return new TextBlock { Text = t, FontFamily = Mono, Foreground = Apagado, FontSize = 11.5, Margin = new Thickness(2, 8, 0, 6) }; }

    Border Cartao(UIElement filho) { return new Border { CornerRadius = new CornerRadius(9), Background = (Brush)w.FindResource("Painel"), BorderBrush = (Brush)w.FindResource("BordaVidro"), BorderThickness = new Thickness(1), Padding = new Thickness(14, 10, 14, 10), Margin = new Thickness(0, 0, 0, 6), Child = filho }; }

    void CarregarDrivers() {
        var p = C<StackPanel>("ListaDrivers");
        p.Children.Clear(); driversMarcaveis.Clear();
        string arq = Path.Combine(dados, "drivers.json");
        if (!File.Exists(arq)) { C<TextBlock>("ResumoDrivers").Text = "driver.scan error · drivers.json não foi gerado"; return; }
        var j = new JavaScriptSerializer { MaxJsonLength = int.MaxValue }.Deserialize<Dictionary<string, object>>(File.ReadAllText(arq, Encoding.UTF8));
        var ups = (ArrayList)j["atualizacoes"];
        var prob = (ArrayList)j["problemas"];
        int antigos = Convert.ToInt32(j["antigos"]);
        string erro = j.ContainsKey("erro") ? (string)j["erro"] : "";
        C<TextBlock>("ResumoDrivers").Text = "driver.scan done · updates=" + ups.Count + " problems=" + prob.Count + " older.3y=" + antigos + (erro.Length > 0 ? " search.error" : "");
        C<TextBlock>("NumeroGrande").Text = ups.Count.ToString("000");
        C<TextBlock>("LegendaGrande").Text = "atualizações de driver";
        if (erro.Length > 0) p.Children.Add(Cartao(new TextBlock { Text = "A busca no Windows Update falhou: " + erro, Foreground = Vermelho, FontSize = 12.5, TextWrapping = TextWrapping.Wrap }));

        if (prob.Count > 0) {
            p.Children.Add(Rotulo("dispositivos com erro"));
            foreach (Dictionary<string, object> d in prob) p.Children.Add(Cartao(new TextBlock { Text = (string)d["nome"] + "  ·  código " + (string)d["codigo"], Foreground = Vermelho, FontSize = 12.5, TextWrapping = TextWrapping.Wrap }));
        }
        if (ups.Count > 0) p.Children.Add(Rotulo("windows update"));
        else if (erro.Length == 0) p.Children.Add(Cartao(new TextBlock { Text = "Nenhuma atualização de driver no catálogo do Windows Update.", Foreground = Medio, FontSize = 12.5 }));
        foreach (Dictionary<string, object> u in ups) {
            var cx = new CheckBox { Style = (Style)w.FindResource("CaixaTitulo"), IsChecked = true, Content = new StackPanel { Children = {
                new TextBlock { Text = (string)u["titulo"], Foreground = Brushes.White, FontSize = 12.5, TextTrimming = TextTrimming.CharacterEllipsis, MaxWidth = 720 },
                new TextBlock { Text = (string)u["classe"] + " · " + (string)u["data"] + " · " + Convert.ToString(u["mb"]) + " MB", FontFamily = Mono, Foreground = Apagado, FontSize = 11 } } } };
            driversMarcaveis.Add(new Achado { Id = (string)u["id"], Caixa = cx });
            p.Children.Add(Cartao(cx));
        }
        var ferr = (ArrayList)j["ferramentas"];
        if (ferr.Count > 0) p.Children.Add(Rotulo("ferramenta do fabricante"));
        foreach (Dictionary<string, object> f in ferr) {
            var cx = new CheckBox { Style = (Style)w.FindResource("CaixaTitulo"), IsChecked = false, Content = (string)f["rotulo"] };
            driversMarcaveis.Add(new Achado { Id = "winget:" + (string)f["id"], Caixa = cx });
            p.Children.Add(Cartao(cx));
        }
        var pag = (ArrayList)j["paginas"];
        var gpu = (ArrayList)j["gpu"];
        if (gpu.Count > 0 || pag.Count > 0) p.Children.Add(Rotulo("placa de vídeo"));
        foreach (Dictionary<string, object> g in gpu) p.Children.Add(Cartao(new StackPanel { Children = {
            new TextBlock { Text = (string)g["nome"], Foreground = Brushes.White, FontSize = 12.5 },
            new TextBlock { Text = "driver " + (string)g["versao"] + " · " + (string)g["data"], FontFamily = Mono, Foreground = Apagado, FontSize = 11 } } }));
        foreach (Dictionary<string, object> s in pag) {
            string url = (string)s["url"];
            var b = new Button { Style = (Style)w.FindResource("BotaoSecundario"), Content = "Abrir site", Width = 100 };
            b.Click += delegate { Process.Start(url); };
            var d = new DockPanel();
            DockPanel.SetDock(b, Dock.Right);
            d.Children.Add(b);
            d.Children.Add(new TextBlock { Text = (string)s["rotulo"] + ": versão mais nova direto do fabricante", Foreground = Medio, FontSize = 12.5, VerticalAlignment = VerticalAlignment.Center });
            p.Children.Add(Cartao(d));
        }
        C<Button>("InstalarDrivers").Visibility = driversMarcaveis.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        C<Button>("InstalarDrivers").IsEnabled = podeAlterar;
    }

    void InstalarDriversMarcados() {
        var ids = driversMarcaveis.Where(a => a.Caixa.IsChecked == true).Select(a => a.Id).ToList();
        if (ids.Count == 0 || emAndamento || !podeAlterar) return;
        if (MessageBox.Show(w, "Instalar " + ids.Count + " item(ns)?\n\nUm ponto de restauração será criado antes. Pode ser preciso reiniciar.", "upaiva.dev", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
        abaDepois = "Drivers"; tipoExec = "ferramenta"; total = ids.Count + 1;
        Executar("drivers.ps1", "-Acao instalar -Ids " + string.Join(",", ids), true, "upaiva › drivers --install " + ids.Count);
    }

// ---------- instalar ----------

    Grupo ObterGrupo(string nome, bool catalogo) {
        var g = grupos.FirstOrDefault(x => x.Nome == nome);
        if (g == null) { g = new Grupo { Nome = nome, Catalogo = catalogo }; grupos.Add(g); }
        return g;
    }

    void Adicionar(string grupo, string rotulo, int peso, params string[] padroes) {
        var i = new Item { Rotulo = rotulo, Peso = peso };
        i.Padroes.AddRange(padroes);
        ObterGrupo(grupo, false).Itens.Add(i);
    }

    static int Tam(Dictionary<string, object> d, string k) { return d.ContainsKey(k) ? ((ICollection)d[k]).Count : 0; }

    void CarregarLista() {
        foreach (var n in new[] { "Dependências (AIO)", "Navegador e utilitários", "Desenvolvimento", "Inteligência artificial", "Comunicação e mídia", "Jogos" }) ObterGrupo(n, false);
        var json = new JavaScriptSerializer { MaxJsonLength = int.MaxValue }.Deserialize<Dictionary<string, object>>(File.ReadAllText(Path.Combine(raiz, "programas.json"), Encoding.UTF8));
        foreach (var lista in new[] { "maquina", "usuario" }) {
            foreach (Dictionary<string, object> p in (ArrayList)json[lista]) {
                string id = (string)p["id"];
                string etapa = "Programa " + (p.ContainsKey("nome") ? (string)p["nome"] : id);
                string rot = p.ContainsKey("rotulo") ? (string)p["rotulo"] : id;
                rotulos[etapa] = rot;
                Adicionar(p.ContainsKey("grupo") ? (string)p["grupo"] : "Outros", rot, 1, etapa);
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
        Adicionar("Skills e configurações", "Skills e configs Claude/Codex", 8 + Tam(json, "marketplaces") + Tam(json, "plugins"), "Restaurar *", "Git com caminhos longos", "Marketplace *", "Plugin *", "Serena*", "Headroom", "Conferir hooks*");
        Adicionar("Skills e configurações", "npm, pip e Python via uv", Tam(json, "npm") + Tam(json, "pip") + Tam(json, "uv_python"), "npm *", "pip *", "Python * via uv");
        Adicionar("Skills e configurações", "Extensões do VS Code", Tam(json, "vscode"), "VS Code *");
        Adicionar("Sistema", "Driver de rede", 1, "Drivers de rede");
        Adicionar("Sistema", ".NET Framework 3.5", 1, "NET Framework 3.5");
        Adicionar("Sistema", "Limpeza do Windows", 1, "Limpeza do Windows");
        if (json.ContainsKey("catalogo")) {
            foreach (Dictionary<string, object> g in (ArrayList)json["catalogo"]) {
                var gr = ObterGrupo("+ " + (string)g["grupo"], true);
                foreach (ArrayList it in (ArrayList)g["itens"]) {
                    string id = (string)it[0], rot = (string)it[1];
                    rotulos["Programa " + id] = rot;
                    gr.Itens.Add(new Item { Rotulo = rot, Id = id, Catalogo = true });
                }
            }
        }
        grupos = grupos.Where(g => g.Itens.Count > 0).ToList();
    }

    void MontarGrupos() {
        var painel = C<StackPanel>("Grupos");
        bool titulo = false;
        foreach (var g in grupos) {
            if (g.Catalogo && !titulo) {
                titulo = true;
                painel.Children.Add(new TextBlock { Text = "catálogo opcional · marque o que quiser, tudo na versão mais nova", FontFamily = Mono, Foreground = Apagado, FontSize = 11.5, Margin = new Thickness(0, 8, 0, 9) });
            }
            var cartao = new Border { CornerRadius = new CornerRadius(12), Background = (Brush)w.FindResource("Painel"), BorderBrush = (Brush)w.FindResource("BordaVidro"), BorderThickness = new Thickness(1), Padding = new Thickness(16, 12, 16, 7), Margin = new Thickness(0, 0, 0, 8) };
            var pilha = new StackPanel();
            var topo = new DockPanel { Margin = new Thickness(0, 0, 0, 9) };
            g.Contador = new TextBlock { FontFamily = Mono, Foreground = Apagado, FontSize = 11.5, VerticalAlignment = VerticalAlignment.Center };
            DockPanel.SetDock(g.Contador, Dock.Right);
            g.Caixa = new CheckBox { Style = (Style)w.FindResource("CaixaTitulo"), Content = new TextBlock { Text = g.Nome, FontWeight = FontWeights.SemiBold, FontSize = 13.5, Foreground = Brushes.White }, IsChecked = !g.Catalogo };
            topo.Children.Add(g.Contador); topo.Children.Add(g.Caixa);
            pilha.Children.Add(topo);
            var itens = new WrapPanel();
            foreach (var i in g.Itens) {
                i.Caixa = new CheckBox { Content = i.Rotulo, IsChecked = !i.Catalogo, Width = 196, Margin = new Thickness(0, 0, 6, 6) };
                i.Caixa.Checked += delegate { Recontar(); };
                i.Caixa.Unchecked += delegate { Recontar(); };
                itens.Children.Add(i.Caixa);
            }
            pilha.Children.Add(itens);
            var gg = g;
            g.Caixa.Click += delegate { atualizando = true; foreach (var i in gg.Itens) i.Caixa.IsChecked = gg.Caixa.IsChecked == true; atualizando = false; Recontar(); };
            cartao.Child = pilha;
            painel.Children.Add(cartao);
        }
    }

    void Recontar() {
        if (atualizando || emAndamento || terminado || abaAtual != "Instalar") { if (atualizando) return; }
        int n = 0;
        foreach (var g in grupos) {
            int m = g.Itens.Count(i => i.Caixa != null && i.Caixa.IsChecked == true);
            if (g.Contador != null) g.Contador.Text = m + "/" + g.Itens.Count;
            if (g.Caixa != null) g.Caixa.IsChecked = m == g.Itens.Count;
            n += m;
        }
        if (abaAtual == "Instalar" && !emAndamento) { var t = C<TextBlock>("NumeroGrande"); if (t != null) t.Text = n.ToString("000"); }
    }

    void IniciarInstalacao() {
        if (emAndamento || !podeAlterar && !semElevar) return;
        Directory.CreateDirectory(Path.GetDirectoryName(logPath));
        var todos = grupos.SelectMany(g => g.Itens).ToList();
        File.WriteAllLines(Path.Combine(dados, "pular.txt"), todos.Where(i => !i.Catalogo && i.Caixa.IsChecked != true).SelectMany(i => i.Padroes), new UTF8Encoding(false));
        File.WriteAllLines(Path.Combine(dados, "catalogo.txt"), todos.Where(i => i.Catalogo && i.Caixa.IsChecked == true).Select(i => i.Id), new UTF8Encoding(false));
        total = todos.Where(i => i.Caixa.IsChecked == true).Sum(i => i.Peso);
        abaDepois = "Instalar"; tipoExec = "instalar";
        // O instalador pede a elevacao so para a parte de maquina.
        Executar("instalar.ps1", "", false, "upaiva › install --all --latest // clique em Sim quando o Windows pedir");
    }

    // ---------- analisar ----------

    void IniciarAnalise() {
        if (emAndamento) return;
        abaDepois = "Analisar"; tipoExec = "analisar"; total = 26;
        Executar("analisar.ps1", C<CheckBox>("Profundo").IsChecked == true ? "-Profundo" : "", !semElevar, "upaiva › scan --security --health --read-only");
    }

    void CarregarAchados() {
        var painel = C<StackPanel>("Achados");
        painel.Children.Clear(); achados.Clear();
        string arq = Path.Combine(dados, "analise.json");
        if (!File.Exists(arq)) { C<TextBlock>("ResumoAnalise").Text = "scanner error · analise.json não foi gerado"; return; }
        var lista = new JavaScriptSerializer { MaxJsonLength = int.MaxValue }.Deserialize<ArrayList>(File.ReadAllText(arq, Encoding.UTF8));
        int crit = 0, alto = 0, med = 0, ok = 0;
        foreach (Dictionary<string, object> a in lista) {
            string sev = (string)a["sev"], id = (string)a["id"];
            if (sev == "CRITICO") crit++; else if (sev == "ALTO") alto++; else if (sev == "MEDIO") med++; else if (sev == "OK") ok++;
            Brush cor = sev == "CRITICO" ? Vermelho : sev == "ALTO" ? Laranja : sev == "MEDIO" ? Amarelo : sev == "OK" ? Bom : Ciano;
            var linha = new DockPanel { Margin = new Thickness(0, 0, 0, 4) };
            var et = new TextBlock { Text = sev.ToLower(), FontFamily = Mono, Foreground = cor, FontSize = 11.5, Width = 66, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(0, 2, 0, 0) };
            DockPanel.SetDock(et, Dock.Left);
            linha.Children.Add(et);
            CheckBox cx = null;
            if (a.ContainsKey("fix") && (bool)a["fix"] && podeAlterar) {
                cx = new CheckBox { Style = (Style)w.FindResource("CaixaTitulo"), Content = "corrigir", IsChecked = false, VerticalAlignment = VerticalAlignment.Top, Margin = new Thickness(8, 0, 0, 0) };
                DockPanel.SetDock(cx, Dock.Right);
                linha.Children.Add(cx);
                achados.Add(new Achado { Id = id, Caixa = cx });
            }
            var txt = new StackPanel();
            txt.Children.Add(new TextBlock { Text = (string)a["titulo"], Foreground = sev == "OK" ? Medio : Brushes.White, FontSize = 12.5, TextWrapping = TextWrapping.Wrap });
            txt.Children.Add(new TextBlock { Text = (string)a["det"], FontFamily = Mono, Foreground = Apagado, FontSize = 11, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 2, 0, 0) });
            linha.Children.Add(txt);
            painel.Children.Add(Cartao(linha));
        }
        C<TextBlock>("ResumoAnalise").Text = "scanner done · crit=" + crit + " high=" + alto + " med=" + med + " ok=" + ok;
        C<Button>("Corrigir").Visibility = achados.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        C<TextBlock>("NumeroGrande").Text = (crit + alto).ToString("000");
        C<TextBlock>("LegendaGrande").Text = "achados graves";
    }

    void CorrigirMarcados() {
        var ids = achados.Where(a => a.Caixa.IsChecked == true).Select(a => a.Id).ToList();
        if (ids.Count == 0 || emAndamento || !podeAlterar) return;
        abaDepois = "Analisar"; tipoExec = "ferramenta"; total = ids.Count;
        Executar("ferramentas.ps1", "-Acao corrigir -Ids " + string.Join(",", ids), true, "upaiva › harden --apply " + string.Join(" ", ids));
    }

    // ---------- otimizar ----------

    void MontarPerfis() {
        var p = C<StackPanel>("Perfis");
        p.Children.Add(new TextBlock { Foreground = Medio, FontSize = 11.5, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 8), Text = "Níveis cumulativos, com backup e ponto de restauração. Nenhum toca em Defender, Firewall, UAC, Windows Update, TPM ou Secure Boot. Ganho de desempenho não é garantido: estes ajustes não têm medição independente." });
        Perfil(p, "leve", "Leve", "risco: nenhum", "Tira ruído sem perder função: anúncios, sugestões, apps instalados sozinhos, Bing no Menu Iniciar. Telemetria no mínimo, Modo de Jogo e Storage Sense ligados, Delivery Optimization sem P2P.", false);
        Perfil(p, "media", "Média", "risco: baixo", "Leve + remove 21 apps (Copilot, Widgets, Teams, Clipchamp, Bing...), desliga Recall e DiagTrack, liga HAGS e plano Alto Desempenho. Na bateria, o notebook dura menos.", true);
        Perfil(p, "alta", "Alta", "perde: impressora, busca indexada, Xbox", "Média + desliga SysMain, Windows Search, Xbox Live, Spooler e relatório de erros. Remove Game Bar e Vincular ao Celular. Hibernação e transparência desligadas, plano Ultimate Performance.", false);
        Perfil(p, "altissima", "Altíssima", "perde: notificações de apps, localização, scanner", "Alta + 13 serviços a menos, apps em segundo plano bloqueados, sem Power Throttling nem Inicialização Rápida, sem armazenamento reservado e sem compressão de memória (RAM >= 16 GB). Para PC de jogo na tomada.", false);
    }

    void Perfil(StackPanel p, string id, string nome, string risco, string texto, bool marcado) {
        var conteudo = new StackPanel();
        var topo = new DockPanel();
        var r = new TextBlock { Text = risco, FontFamily = Mono, Foreground = Laranja, FontSize = 11, VerticalAlignment = VerticalAlignment.Center };
        DockPanel.SetDock(r, Dock.Right);
        topo.Children.Add(r);
        topo.Children.Add(new TextBlock { Text = nome, Foreground = Brushes.White, FontWeight = FontWeights.SemiBold, FontSize = 14 });
        conteudo.Children.Add(topo);
        conteudo.Children.Add(new TextBlock { Text = texto, Foreground = Medio, FontSize = 12.5, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 5, 0, 0), LineHeight = 18 });
        var b = new RadioButton { Style = (Style)w.FindResource("Perfil"), GroupName = "Perfis", Content = conteudo, IsChecked = marcado };
        var i = id;
        b.Checked += delegate { nivelEscolhido = i; AtualizarPainel(); };
        p.Children.Add(b);
    }

    void RodarOtimizar(bool simular, bool reverter) {
        if (emAndamento || (!simular && !podeAlterar)) return;
        if (!simular && !reverter && MessageBox.Show(w, "Aplicar o nível " + nivelEscolhido.ToUpper() + "?\n\nUm ponto de restauração será criado e o estado anterior fica salvo para reverter.", "upaiva.dev", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
        if (reverter && MessageBox.Show(w, "Reverter serviços e registro ao estado salvo?\n\nApps removidos voltam pela Microsoft Store.", "upaiva.dev", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
        string a = reverter ? "-Reverter" : "-Nivel " + nivelEscolhido + (simular ? " -Simular" : "");
        if (C<CheckBox>("OpcaoVBS").IsChecked == true && !reverter) a += " -DesligarVBS";
        abaDepois = "Otimizar"; tipoExec = "ferramenta"; total = 0;
        Executar("otimizar.ps1", a, !simular, "upaiva › optimize " + (reverter ? "--revert" : "--profile=" + nivelEscolhido + (simular ? " --dry-run" : "")));
    }

    // ---------- ferramentas ----------

    void MontarFerramentas() {
        var p = C<StackPanel>("Ferramentas");
        Ferramenta(p, "atualizar", "Atualizar todos os programas", "winget upgrade --all --include-unknown");
        Ferramenta(p, "limpar", "Limpar disco", "purge %TEMP% e %WINDIR%\\Temp; DISM /StartComponentCleanup");
        Ferramenta(p, "reparar", "Reparar sistema", "DISM /RestoreHealth; sfc /scannow (pode levar 30 min)");
        Ferramenta(p, "rede", "Resetar rede", "ipconfig /flushdns; netsh winsock reset; netsh int ip reset (reinicie depois)");
        Ferramenta(p, "restauracao", "Criar ponto de restauração", "Enable-ComputerRestore; Checkpoint-Computer");
    }

    void Ferramenta(StackPanel p, string acao, string titulo, string det) {
        var g = new DockPanel();
        var b = new Button { Style = (Style)w.FindResource("BotaoSecundario"), Content = "Rodar", Width = 90, VerticalAlignment = VerticalAlignment.Center };
        DockPanel.SetDock(b, Dock.Right);
        g.Children.Add(b);
        var t = new StackPanel();
        t.Children.Add(new TextBlock { Text = titulo, Foreground = Brushes.White, FontWeight = FontWeights.SemiBold, FontSize = 13.5 });
        t.Children.Add(new TextBlock { Text = det, FontFamily = Mono, Foreground = Apagado, FontSize = 11.5, Margin = new Thickness(0, 4, 8, 0), TextWrapping = TextWrapping.Wrap });
        g.Children.Add(t);
        var i = acao;
        b.IsEnabled = podeAlterarInicial();
        b.Click += delegate {
            if (emAndamento || !podeAlterar) return;
            abaDepois = "Ferramentas"; tipoExec = "ferramenta"; total = 0;
            Executar("ferramentas.ps1", "-Acao " + i, true, "upaiva › tool " + i);
        };
        p.Children.Add(Cartao(g));
    }

    bool podeAlterarInicial() { return !string.Equals(Environment.GetEnvironmentVariable("COMPUTERNAME"), "MARINETE", StringComparison.OrdinalIgnoreCase); }

    // ---------- execucao ----------

    void Executar(string script, string argumentos, bool elevado, string prompt) {
        Directory.CreateDirectory(Path.GetDirectoryName(logPath));
        posicaoLog = File.Exists(logPath) ? new FileInfo(logPath).Length : 0;
        resto = ""; concluidas = 0; falhas = 0; terminado = false;
        linhas.Clear();
        C<StackPanel>("Etapas").Children.Clear();
        string cmd = "-NoProfile -ExecutionPolicy Bypass -File \"" + Path.Combine(raiz, "scripts", script) + "\" " + argumentos;
        ProcessStartInfo psi;
        if (elevado) psi = new ProcessStartInfo("powershell.exe", cmd) { UseShellExecute = true, Verb = "runas", WindowStyle = ProcessWindowStyle.Hidden };
        else {
            psi = new ProcessStartInfo("powershell.exe", cmd) { UseShellExecute = false, CreateNoWindow = true };
            psi.EnvironmentVariables["SETUP_GUI"] = "1";
            psi.EnvironmentVariables.Remove("PSModulePath");
            psi.EnvironmentVariables["SETUP_DADOS"] = dados;
        }
        Term("$ powershell " + cmd.Replace(raiz + "\\", ""));
        try { processo = Process.Start(psi); }
        catch (Exception e) { Term("exec.denied " + e.Message); AvisoFixo("O Windows não recebeu permissão de administrador: nada foi feito."); return; }
        emAndamento = true;
        inicioExec = DateTime.Now;
        Term("proc.spawn pid=" + processo.Id + " elevated=" + elevado);
        Digitar(prompt);
        C<RadioButton>("AbaTerminal").IsChecked = true;
        C<ProgressBar>("Barra").Visibility = Visibility.Visible;
        C<ProgressBar>("Barra").Value = 0;
        C<TextBlock>("NumeroGrande").Text = "000%";
        C<TextBlock>("LegendaGrande").Text = "concluído";
        C<TextBlock>("Situacao").Foreground = Medio;
        C<TextBlock>("Aviso").Visibility = Visibility.Collapsed;
        C<Button>("Relatorio").Visibility = Visibility.Collapsed;
        situacaoBase = "Preparando";
        AtualizarPainel();
        relogio = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(350) };
        relogio.Tick += delegate { LerLog(); if (processo.HasExited) { relogio.Stop(); LerLog(); Finalizar(); } };
        relogio.Start();
    }

    void Term(string l) {
        var t = C<RichTextBox>("Terminal");
        Brush cor = Medio;
        if (l.StartsWith("$ ")) cor = Ciano;
        else if (l.StartsWith("proc.") || l.StartsWith("exec.")) cor = Violeta;
        else if (l.StartsWith("  |")) cor = Apagado;
        else if (l.StartsWith("[ ok ]") || l.StartsWith("[pulado]")) cor = Bom;
        else if (l.StartsWith("[FALHOU]") || l.Contains("policy.deny") || l.StartsWith("ui.error")) cor = Vermelho;
        else if (l.StartsWith("[....]")) cor = Brushes.White;
        var p = new Paragraph { Margin = new Thickness(0), LineHeight = 16 };
        p.Inlines.Add(new Run(DateTime.Now.ToString("HH:mm:ss") + "  ") { Foreground = Apagado });
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

    void ProcessarLinha(string bruta) {
        var m = RxLinha.Match(bruta);
        string l = m.Success ? m.Groups[1].Value : bruta;
        if (l.Length == 0 || l.StartsWith("[ignorado] ")) return;
        if (l.StartsWith("@total ")) { int v; if (int.TryParse(l.Substring(7), out v) && tipoExec != "instalar") total = v; return; }
        Term(l);
        if (l.StartsWith("[....] ")) { var n = l.Substring(7); Marcar(n, ">>", Ciano, ""); situacaoBase = Nome(n); }
        else if (l.StartsWith("[ ok ] ")) { Marcar(l.Substring(7), "OK", Bom, ""); concluidas++; }
        else if (l.StartsWith("[pulado] ")) { var n = l.Substring(9).Replace(" (ja feito)", ""); Marcar(n, "OK", Medio, "já estava feito"); concluidas++; }
        else if (l.StartsWith("[FALHOU] ")) {
            string r = l.Substring(9); int s = r.IndexOf(" - ");
            string n = s >= 0 ? r.Substring(0, s) : r, d = s >= 0 ? r.Substring(s + 3) : "";
            Marcar(n, "!!", Vermelho, d.Replace("FALHA: ", "")); falhas++; concluidas++;
        }
        else if (l.StartsWith("Sem internet")) { var a = C<TextBlock>("Aviso"); a.Text = l; a.Foreground = Laranja; a.Visibility = Visibility.Visible; }
        else if (l.StartsWith("Etapa ")) { situacaoBase = l; C<TextBlock>("Aviso").Visibility = Visibility.Collapsed; }
        int pct = total > 0 ? Math.Min(99, concluidas * 100 / total) : 0;
        C<ProgressBar>("Barra").Value = pct;
        C<TextBlock>("NumeroGrande").Text = pct.ToString("000") + "%";
    }

    string Nome(string etapa) {
        string r;
        if (rotulos.TryGetValue(etapa, out r)) return r;
        return etapa.StartsWith("Programa ") ? etapa.Substring(9) : etapa;
    }

    void Marcar(string etapa, string etiqueta, Brush cor, string detalhe) {
        Linha l;
        if (!linhas.TryGetValue(etapa, out l)) {
            l = new Linha {
                Etiqueta = new TextBlock { FontFamily = Mono, FontSize = 12, Width = 38, VerticalAlignment = VerticalAlignment.Center },
                Texto = new TextBlock { Text = Nome(etapa), Foreground = Medio, FontSize = 13, VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis },
                Detalhe = new TextBlock { Foreground = Apagado, FontSize = 11.5, VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis, Margin = new Thickness(10, 0, 0, 0) }
            };
            var linha = new DockPanel { Margin = new Thickness(0, 0, 0, 3) };
            DockPanel.SetDock(l.Etiqueta, Dock.Left);
            DockPanel.SetDock(l.Detalhe, Dock.Right);
            linha.Children.Add(l.Etiqueta); linha.Children.Add(l.Detalhe); linha.Children.Add(l.Texto);
            C<StackPanel>("Etapas").Children.Add(linha);
            linhas[etapa] = l;
            C<ScrollViewer>("RolagemEtapas").ScrollToEnd();
        }
        l.Etiqueta.Text = "[" + etiqueta + "]"; l.Etiqueta.Foreground = cor; l.Detalhe.Text = detalhe;
    }

    void Finalizar() {
        emAndamento = false;
        terminado = true;
        situacaoBase = "";
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
        C<ProgressBar>("Barra").Value = 100;
        C<TextBlock>("NumeroGrande").Text = falhou == 0 ? "100%" : falhou.ToString("000");
        C<TextBlock>("LegendaGrande").Text = falhou == 0 ? "concluído" : (falhou == 1 ? "item falhou" : "itens falharam");
        Digitar(falhou == 0 ? "upaiva › exit 0 // concluído" : "upaiva › exit 1 // rode de novo: refaz só o que faltou");
        var st = C<TextBlock>("Situacao");
        st.Foreground = falhou == 0 ? Destaque : Vermelho;
        st.Text = falhou > 0 ? string.Join("\n", apontados.Take(5).Select(a => "! " + a)) : (tipoExec == "instalar" ? "Reinicie o PC e depois faça login nos programas." : "Terminou. Veja as linhas no terminal.");
        if (manual > 0) { var av = C<TextBlock>("Aviso"); av.Text = "Falta instalar à mão: veja o relatório."; av.Foreground = Laranja; av.Visibility = Visibility.Visible; }
        var b = C<Button>("Principal");
        b.Visibility = Visibility.Visible; b.IsEnabled = true; b.Content = "Voltar";
        if (tipoExec == "analisar") CarregarAchados();
        if (tipoExec == "drivers") CarregarDrivers();
        if (arqFotoFim != null) {
            var t = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(1500) };
            t.Tick += delegate {
                t.Stop();
                if (tipoExec == "analisar") { C<RadioButton>("AbaAnalisar").IsChecked = true; }
                if (tipoExec == "drivers") { C<RadioButton>("AbaDrivers").IsChecked = true; }
                w.Dispatcher.BeginInvoke(DispatcherPriority.Background, new Action(delegate {
                    Fotografar(arqFotoFim);
                    File.WriteAllText(arqFotoFim + ".txt", "falhou=" + falhou + " manual=" + manual + " linhas=" + linhas.Count + " concluidas=" + concluidas + " total=" + total + " term=" + C<RichTextBox>("Terminal").Document.Blocks.Count);
                    Application.Current.Shutdown();
                }));
            };
            t.Start();
        }
    }

    void Demonstrar() {
        total = 12; tipoExec = "ferramenta"; emAndamento = true; inicioExec = DateTime.Now.AddMinutes(-7);
        C<RadioButton>("AbaTerminal").IsChecked = true;
        C<ProgressBar>("Barra").Visibility = Visibility.Visible;
        Digitar("upaiva › install --latest");
        foreach (var l in new[] {
            "10:00:01 Etapa 1 de 3: programas do sistema. Clique em Sim no aviso do Windows.",
            "10:00:02 [ ok ] Drivers de rede",
            "10:00:03 [ ok ] Programa Microsoft.VCRedist.2015+.x64",
            "10:00:04 [pulado] Programa Microsoft.DirectX (ja feito)",
            "10:00:05 [ ok ] Programa Google.Chrome",
            "10:00:06 [FALHOU] Programa Microsoft.XNARedist - FALHA: nao aparece no winget (codigo 1460)",
            "10:00:08 [....] Programa Discord.Discord",
            "10:00:08 $ winget.exe install --id \"Discord.Discord\" --exact --source winget --silent",
            "10:00:08 proc.spawn winget.exe pid=18244 timeout=25m",
            "10:00:11   | Found Discord [Discord.Discord] Version 1.0.9267",
            "10:00:12   | Downloading https://stable.dl2.discordapp.net/distro/app/stable/win/x64/DiscordSetup.exe",
            "10:00:19   | Successfully verified installer hash" }) ProcessarLinha(l);
    }
}
