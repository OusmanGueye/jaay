package sn.ardoise.ardoise

import android.app.Presentation
import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.hardware.display.DisplayManager
import android.os.Bundle
import android.view.Display
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Petit écran client du terminal (ZCS Z108) : affiche uniquement la vente en cours. */
class CustomerPresentation(ctx: Context, display: Display) : Presentation(ctx, display) {
    private val root = LinearLayout(ctx)
    private val shop = TextView(ctx)
    private val body = LinearLayout(ctx)
    private val totalLabel = TextView(ctx)
    private val total = TextView(ctx)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        root.orientation = LinearLayout.VERTICAL
        root.setBackgroundColor(Color.parseColor("#102A43"))
        root.setPadding(24, 16, 24, 16)

        shop.setTextColor(Color.WHITE)
        shop.textSize = 18f
        shop.typeface = Typeface.DEFAULT_BOLD
        shop.gravity = Gravity.CENTER
        root.addView(shop)

        body.orientation = LinearLayout.VERTICAL
        root.addView(body, LinearLayout.LayoutParams(-1, 0, 1f))

        totalLabel.text = "TOTAL"
        totalLabel.setTextColor(Color.parseColor("#9FB3C8"))
        totalLabel.textSize = 12f
        totalLabel.gravity = Gravity.CENTER
        root.addView(totalLabel)

        total.setTextColor(Color.parseColor("#7CE0A3"))
        total.textSize = 30f
        total.typeface = Typeface.DEFAULT_BOLD
        total.gravity = Gravity.CENTER
        root.addView(total)

        setContentView(root)
    }

    @Suppress("UNCHECKED_CAST")
    fun render(args: Map<String, Any?>) {
        shop.text = (args["shop"] as? String) ?: ""
        val lines = (args["lines"] as? List<Map<String, Any?>>) ?: emptyList()
        body.removeAllViews()
        if (lines.isEmpty()) {
            val hi = TextView(context)
            hi.text = (args["footer"] as? String)?.takeIf { it.isNotBlank() } ?: "Bienvenue"
            hi.setTextColor(Color.WHITE)
            hi.textSize = 16f
            hi.gravity = Gravity.CENTER
            body.addView(hi, LinearLayout.LayoutParams(-1, -1))
            total.visibility = View.GONE
            totalLabel.visibility = View.GONE
        } else {
            total.visibility = View.VISIBLE
            totalLabel.visibility = View.VISIBLE
            for (l in lines) {
                val row = LinearLayout(context)
                row.orientation = LinearLayout.HORIZONTAL
                val name = TextView(context)
                name.text = "${l["name"]}\n${l["detail"]}"
                name.setTextColor(Color.WHITE)
                name.textSize = 13f
                val amount = TextView(context)
                amount.text = "${l["total"]}"
                amount.setTextColor(Color.WHITE)
                amount.textSize = 14f
                amount.gravity = Gravity.END or Gravity.CENTER_VERTICAL
                row.addView(name, LinearLayout.LayoutParams(0, -2, 1f))
                row.addView(amount, LinearLayout.LayoutParams(-2, -2))
                row.setPadding(0, 6, 0, 6)
                body.addView(row)
            }
            total.text = (args["total"] as? String) ?: ""
        }
    }
}

class MainActivity : FlutterActivity() {
    private var presentation: CustomerPresentation? = null

    private fun secondDisplay(): Display? {
        val dm = getSystemService(Context.DISPLAY_SERVICE) as DisplayManager
        val list = dm.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION)
        if (list.isNotEmpty()) return list[0]
        return dm.displays.firstOrNull { it.displayId != Display.DEFAULT_DISPLAY }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "gueye/customer_display")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "available" -> result.success(secondDisplay() != null)
                        "show" -> {
                            val d = secondDisplay()
                            if (d == null) {
                                result.success(false)
                            } else {
                                if (presentation == null || presentation?.display?.displayId != d.displayId) {
                                    presentation?.dismiss()
                                    presentation = CustomerPresentation(this, d).also { it.show() }
                                }
                                @Suppress("UNCHECKED_CAST")
                                presentation?.render(call.arguments as Map<String, Any?>)
                                result.success(true)
                            }
                        }
                        "hide" -> {
                            presentation?.dismiss()
                            presentation = null
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.success(false)
                }
            }
    }

    override fun onDestroy() {
        presentation?.dismiss()
        presentation = null
        super.onDestroy()
    }
}
