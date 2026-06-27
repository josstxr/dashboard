import "@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from 'npm:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface FoodAnalysisResponse {
  name: string
  calories: number
  protein: number
  carbs: number
  fats: number
  estimated_grams: number
  confidence: number
  items: Array<{
    name: string
    estimated_grams: number
    calories: number
  }>
}

// Función auxiliar para convertir Uint8Array a base64
function uint8ArrayToBase64(arr: Uint8Array): string {
  let binary = '';
  for (let i = 0; i < arr.byteLength; i++) {
    binary += String.fromCharCode(arr[i]);
  }
  return btoa(binary);
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: req.headers.get('Authorization')! } } }
    )

    const { data: { user }, error: userError } = await supabaseClient.auth.getUser()
    if (userError || !user) {
      return new Response(
        JSON.stringify({ error: 'No autenticado' }), 
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const formData = await req.formData()
    const file = formData.get('file') as File
    
    if (!file) {
      return new Response(
        JSON.stringify({ error: 'Archivo de imagen no encontrado' }), 
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const arrayBuffer = await file.arrayBuffer()
    const uint8Array = new Uint8Array(arrayBuffer)
    const base64Image = uint8ArrayToBase64(uint8Array)

    const geminiApiKey = Deno.env.get('GEMINI_API_KEY')
    if (!geminiApiKey) {
      console.warn('GEMINI_API_KEY not configured')
      return new Response(
        JSON.stringify({ error: 'Configuración de API incompleta. Configura GEMINI_API_KEY en Supabase.' }), 
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const result = await analyzeFoodImageWithGemini(geminiApiKey, base64Image)

    return new Response(JSON.stringify(result), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    })
  } catch (error: any) {
    console.error('Error analyzing food:', error)
    return new Response(
      JSON.stringify({ error: error.message || 'Error al analizar la imagen' }), 
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500,
      }
    )
  }
})

async function analyzeFoodImageWithGemini(apiKey: string, base64Image: string): Promise<FoodAnalysisResponse> {
  const payload = {
    contents: [
      {
        parts: [
          {
            text: "Analiza la imagen de comida y estima la porcion visible. Responde UNICAMENTE JSON valido con esta forma exacta: {\"name\":\"nombre breve del plato en espanol\",\"calories\":0,\"protein\":0,\"carbs\":0,\"fats\":0,\"estimated_grams\":0,\"confidence\":0,\"items\":[{\"name\":\"alimento\",\"estimated_grams\":0,\"calories\":0}]}. calories/protein/carbs/fats deben ser el total estimado de toda la porcion visible, no por 100g. Si la imagen no contiene comida, usa name=\"No se detecto comida\" y todos los numeros en 0. No incluyas texto fuera del JSON.",
          },
          {
            inline_data: {
              mime_type: "image/jpeg",
              data: base64Image,
            },
          },
        ],
      },
    ],
    generationConfig: {
      response_mime_type: "application/json",
      temperature: 0.2,
    },
  }

  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${apiKey}`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
    }
  )

  if (!response.ok) {
    const errorData = await response.json()
    throw new Error(`Gemini API error: ${JSON.stringify(errorData)}`)
  }

  const data = await response.json()
  
  if (!data.candidates?.[0]?.content?.parts?.[0]?.text) {
    throw new Error('No response from Gemini API')
  }

  const responseText = data.candidates[0].content.parts[0].text
  
  try {
    const parsed = JSON.parse(responseText) as FoodAnalysisResponse
    return parsed
  } catch (e) {
    console.error('Failed to parse Gemini response:', responseText)
    throw new Error('Invalid response format from Gemini')
  }
}
