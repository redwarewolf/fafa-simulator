using UnityEngine;
using UnityEngine.UI;
using System.Collections;
using UnityEngine.EventSystems;

public class DragHandler : MonoBehaviour, IBeginDragHandler, IDragHandler, IEndDragHandler
{
    public static GameObject item;

    Vector3 startPosition; 
    Transform startParent;

    public void OnBeginDrag(PointerEventData eventData)
    {
        item = gameObject;

        startPosition = transform.position;
        startParent = transform.parent;

        GetComponent<CanvasGroup>().blocksRaycasts = false;
    }

    public void OnDrag(PointerEventData eventData)
    {
        transform.position = Input.mousePosition;
    }

    public void OnEndDrag(PointerEventData eventData)
    {

        item = null;
        transform.position = startPosition;
        GetComponent<CanvasGroup>().blocksRaycasts = true;

        if(transform.parent == startParent){
            transform.position = startPosition;
        }        
    }
}