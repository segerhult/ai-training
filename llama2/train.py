# Load model directly
from transformers import AutoTokenizer, AutoModelForCausalLM

tokenizer = AutoTokenizer.from_pretrained("NousResearch/Llama-2-7b-chat-hf")
model = AutoModelForCausalLM.from_pretrained("NousResearch/Llama-2-7b-chat-hf")

device =  "cpu"

def generate_response(input_text):
    inputs = tokenizer(input_text, return_tensors="pt")
    reply_ids = model.generate(inputs.input_ids.to(device), max_length=200, num_return_sequences=1, do_sample=True)
    reply = tokenizer.decode(reply_ids[0], skip_special_tokens=True)
    return reply

print("Bot: Hi there! Ask me anything about network protocols or OSPF.")
while True:
    user_input = input("User: ")
    if user_input.lower() == "exit":
        print("Bot: Goodbye!")
        break

    response = generate_response(user_input)
    print("Bot:", response)
