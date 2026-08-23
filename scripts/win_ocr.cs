using System;
using System.IO;
using System.Threading.Tasks;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using Windows.Storage;

namespace OfflineOcr
{
    class Program
    {
        static void Main(string[] args)
        {
            if (args.Length == 0)
            {
                Console.WriteLine("Usage: win_ocr.exe <image_path>");
                return;
            }

            string imagePath = Path.GetFullPath(args[0]);
            if (!File.Exists(imagePath))
            {
                Console.WriteLine("File not found: " + imagePath);
                return;
            }

            try
            {
                var task = RunOcr(imagePath);
                task.Wait();
            }
            catch (Exception ex)
            {
                Console.WriteLine("OCR_ERROR: " + (ex.InnerException != null ? ex.InnerException.Message : ex.Message));
            }
        }

        static async Task RunOcr(string imagePath)
        {
            StorageFile file = await StorageFile.GetFileFromPathAsync(imagePath);
            using (var stream = await file.OpenAsync(FileAccessMode.Read))
            {
                BitmapDecoder decoder = await BitmapDecoder.CreateAsync(stream);
                SoftwareBitmap bitmap = await decoder.GetSoftwareBitmapAsync();

                OcrEngine engine = OcrEngine.TryCreateFromUserProfileLanguages();
                if (engine == null)
                {
                    engine = OcrEngine.TryCreateFromLanguage(new Windows.Globalization.Language("en-US"));
                }

                if (engine == null)
                {
                    Console.WriteLine("NO_OCR_ENGINE");
                    return;
                }

                OcrResult result = await engine.RecognizeAsync(bitmap);
                foreach (var line in result.Lines)
                {
                    Console.WriteLine(line.Text);
                }
            }
        }
    }
}
