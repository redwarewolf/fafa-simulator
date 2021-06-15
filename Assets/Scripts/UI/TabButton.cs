using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class TabButton : MonoBehaviour
{
    public GameObject panel;
    public TabGroup tabGroup { get; set; }

    void Awake()
    {
        tabGroup = gameObject.GetComponentInParent<TabGroup>();
    }

    public void OnClick()
    {
        tabGroup.activatePanel(panel);
    }
}
