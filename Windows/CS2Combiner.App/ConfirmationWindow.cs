using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;

namespace CS2Combiner.App;

public sealed class ConfirmationWindow : Window
{
    public ConfirmationWindow(
        string title,
        string message,
        bool showsCancel = true,
        string? confirmText = null,
        string? cancelText = null)
    {
        Title = title;
        Width = 520;
        SizeToContent = SizeToContent.Height;
        MinHeight = 180;
        MaxHeight = 620;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        CanResize = false;

        var confirm = new Button
        {
            Content = confirmText ?? (showsCancel ? "Replace" : "OK"),
            MinWidth = 88,
            HorizontalAlignment = HorizontalAlignment.Right,
            HorizontalContentAlignment = HorizontalAlignment.Center,
            VerticalContentAlignment = VerticalAlignment.Center
        };
        confirm.Click += (_, _) => Close(true);

        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            Spacing = 8
        };
        if (showsCancel)
        {
            var cancel = new Button
            {
                Content = cancelText ?? "Cancel",
                MinWidth = 88,
                HorizontalContentAlignment = HorizontalAlignment.Center,
                VerticalContentAlignment = VerticalAlignment.Center
            };
            cancel.Click += (_, _) => Close(false);
            buttons.Children.Add(cancel);
        }
        buttons.Children.Add(confirm);

        Content = new StackPanel
        {
            Margin = new(22),
            Spacing = 18,
            Children =
            {
                new TextBlock
                {
                    Text = message,
                    TextWrapping = TextWrapping.Wrap,
                    MaxHeight = 460
                },
                buttons
            }
        };
    }
}
