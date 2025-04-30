import requests
from fastapi import FastAPI, File, UploadFile, Query, HTTPException
from pydantic import BaseModel
from typing import List
from fastapi.middleware.cors import CORSMiddleware
from pyzbar.pyzbar import decode
from PIL import Image
from io import BytesIO
import magic  
import zxing  # Import Zxing library

app = FastAPI()

# CORS setup
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Response schema
class AllergenDetails(BaseModel):
    name: str

class AllergensResponse(BaseModel):
    allergens: List[AllergenDetails]

# Check if the uploaded file is a valid image
def is_valid_image(image_data: bytes) -> bool:
    mime = magic.Magic(mime=True)
    mime_type = mime.from_buffer(image_data)
    print(f"Detected MIME type: {mime_type}")
    return mime_type.startswith('image/')

# Decode the barcode from the image using pyzbar, fallback to Zxing
def decode_barcode(image_data: bytes) -> str:
    if not is_valid_image(image_data):
        raise HTTPException(status_code=400, detail="The uploaded file is not a valid image.")
    
    # Try using pyzbar first
    try:
        image = Image.open(BytesIO(image_data))
        barcodes = decode(image)
        if barcodes:
            barcode_data = barcodes[0].data.decode('utf-8')
            print(f"Decoded barcode data using pyzbar: {barcode_data}")
            return barcode_data
    except Exception as e:
        print(f"Error with pyzbar: {str(e)}")
    
    # Fallback to Zxing if pyzbar fails
    try:
        reader = zxing.BarCodeReader()
        barcode = reader.decode(image_data)
        if barcode and barcode.raw:
            barcode_data = barcode.raw.decode('utf-8')
            print(f"Decoded barcode data using Zxing: {barcode_data}")
            return barcode_data
    except Exception as e:
        print(f"Error with Zxing: {str(e)}")

    raise HTTPException(status_code=400, detail="No barcode detected in the image.")

# Retrieve product data from Open Food Facts
def get_product_data(barcode_data: str):
    url = f"https://world.openfoodfacts.org/api/v0/product/{barcode_data}.json"
    print(f"Requesting data from Open Food Facts for barcode: {barcode_data}")
    try:
        response = requests.get(url)
        response.raise_for_status()
        print(f"Received response: {response.status_code}")
        product_data = response.json()
        print(f"Received product data: {product_data}")
        return product_data
    except requests.exceptions.RequestException as e:
        print(f"Error during API request: {str(e)}")
        raise HTTPException(status_code=500, detail=f"Error retrieving product data: {str(e)}")

# Check allergens against tags and fallback to raw text
ALLERGEN_KEYWORDS = {
    "milk": ["milk", "milk powder", "whey", "casein", "lactose", "butter", "cheese", "cream", "yogurt"],
    "eggs": ["egg", "eggs", "albumen", "egg white", "egg yolk", "mayonnaise"],
    "fish": ["fish", "salmon", "tuna", "cod", "haddock", "sardine", "anchovy", "trout", "bass", "snapper"],
    "shellfish": ["shrimp", "crab", "lobster", "prawn", "scampi", "crayfish", "shellfish"],
    "tree nuts": ["almond", "walnut", "cashew", "pistachio", "pecan", "hazelnut", "macadamia", "brazil nut", "chestnut", "pine nut"],
    "peanuts": ["peanut", "groundnut", "monkey nut", "peanut butter"],
    "wheat": ["wheat", "gluten", "bread flour", "semolina", "spelt", "farro", "durum"],
    "soy": ["soy", "soya", "soybean", "soy lecithin", "edamame"],
    "sesame": ["sesame", "sesame seeds", "tahini"],
}

def check_allergens(product_data: dict, user_allergens: List[str]) -> List[str]:
    ingredients = product_data.get("product", {}).get("ingredients_text", "").lower()
    traces = product_data.get("product", {}).get("traces_from_ingredients", "").lower()
    warnings = product_data.get("product", {}).get("warnings", "").lower()

    combined_text = f"{ingredients} {traces} {warnings}"

    found = set()

    for user_allergen in user_allergens:
        user_allergen = user_allergen.lower()

        # Check direct match first
        if user_allergen in combined_text:
            found.add(user_allergen)

        # Then use the keyword map
        if user_allergen in ALLERGEN_KEYWORDS:
            for keyword in ALLERGEN_KEYWORDS[user_allergen]:
                if keyword.lower() in combined_text:
                    found.add(user_allergen)
                    break

    print(f"Matched allergens: {found}")
    return list(found)

# Upload route for barcode scanning
@app.post("/upload", response_model=AllergensResponse)
async def upload_image(
    image: UploadFile = File(...),
    allergens: str = Query("", alias="allergens")
):
    try:
        barcode_data = decode_barcode(await image.read())
    except Exception as e:
        print(f"Error decoding barcode: {str(e)}")
        raise HTTPException(status_code=400, detail=str(e))

    try:
        product_data = get_product_data(barcode_data)
    except HTTPException as e:
        print(f"Error retrieving product data: {str(e)}")
        raise e

    ingredients = product_data.get("product", {}).get("ingredients_text", "")
    traces = product_data.get("product", {}).get("traces_from_ingredients", "")
    if not ingredients and not traces:
        print("No ingredients or traces found.")
        raise HTTPException(status_code=404, detail="No ingredients or traces information available.")

    print(f"Ingredients: {ingredients}")
    print(f"Traces: {traces}")

    allergen_list = [a.strip().lower() for a in allergens.split(",") if a.strip()]
    if not allergen_list:
        print("No allergens provided.")
        raise HTTPException(status_code=400, detail="Please provide at least one allergen.")

    found_allergens = check_allergens(product_data, allergen_list)

    if not found_allergens:
        print("No allergens found.")
        raise HTTPException(status_code=404, detail="None of the allergens specified were found in the product.")

    found_allergen_details = [AllergenDetails(name=a) for a in found_allergens]
    print(f"Found allergens: {found_allergen_details}")
    return AllergensResponse(allergens=found_allergen_details)
